/**
 * One WebSocket connection to one running Godot editor.
 *
 * Protocol (see addon/godot_pilot/bridge/bridge_server.gd):
 * 1. We send {"type": "hello", "token": ...}; the editor answers "hello_ok" or closes.
 * 2. We send {"type": "request", "id", "method", "params"}; the editor answers with
 *    {"type": "response", "id", "ok": true, "result"} or {"ok": false, "error"}.
 * Several requests can be in flight at the same time; the id matches answers to them.
 */
import { PRODUCT_NAME, PRODUCT_VERSION } from "../product.ts";
import { type EditorRegistration, isProcessAlive } from "./editor-registry.ts";

const HANDSHAKE_TIMEOUT_MILLISECONDS = 10_000;
export const DEFAULT_REQUEST_TIMEOUT_MILLISECONDS = 60_000;
const NORMAL_CLOSE_CODE = 1000;

/** An error reported by the Godot addon, with a hint for the AI on how to fix the call. */
export class EditorRequestError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly hint?: string,
    readonly details?: unknown,
  ) {
    super(message);
    this.name = "EditorRequestError";
  }
}

/** Who is connecting, shown in the Godot Pilot panel of the editor. */
export interface ClientDescription {
  /** Name of the AI application, for example "claude-code". */
  aiClient: string;
  permissionMode: string;
}

interface PendingRequest {
  method: string;
  resolve: (result: unknown) => void;
  reject: (error: Error) => void;
  timeoutTimer: ReturnType<typeof setTimeout>;
}

interface ResponseMessage {
  type: "response";
  id: number;
  ok: boolean;
  result?: unknown;
  error?: { code?: string; message?: string; hint?: string; details?: unknown };
}

export class EditorConnection {
  private socket: WebSocket | null = null;
  private nextRequestId = 1;
  private readonly pendingRequests = new Map<number, PendingRequest>();
  private isClosed = false;

  constructor(
    readonly registration: EditorRegistration,
    private readonly describeClient: () => ClientDescription = () => ({
      aiClient: "unknown",
      permissionMode: "full",
    }),
  ) {}

  get isOpen(): boolean {
    return !this.isClosed && this.socket?.readyState === WebSocket.OPEN;
  }

  /** Connects and authenticates. Resolves once the editor has accepted our token. */
  open(): Promise<void> {
    return new Promise((resolve, reject) => {
      const socket = new WebSocket(`ws://127.0.0.1:${this.registration.port}`);
      this.socket = socket;
      let isAuthenticated = false;

      const handshakeTimer = setTimeout(() => {
        socket.close(NORMAL_CLOSE_CODE, "Handshake timed out");
        reject(new Error(`The Godot editor on port ${this.registration.port} did not answer in time.`));
      }, HANDSHAKE_TIMEOUT_MILLISECONDS);

      socket.addEventListener("open", () => {
        const clientDescription = this.describeClient();
        socket.send(
          JSON.stringify({
            type: "hello",
            token: this.registration.token,
            client: {
              name: PRODUCT_NAME,
              version: PRODUCT_VERSION,
              ai_client: clientDescription.aiClient,
              permission_mode: clientDescription.permissionMode,
            },
          }),
        );
      });

      socket.addEventListener("message", (event) => {
        const message = parseMessage(event.data);
        if (!message) {
          return;
        }
        if (!isAuthenticated) {
          clearTimeout(handshakeTimer);
          if (message.type === "hello_ok") {
            isAuthenticated = true;
            resolve();
          } else {
            reject(
              new Error(`The Godot editor refused the connection: ${String(message.reason ?? message.type)}`),
            );
          }
          return;
        }
        if (message.type === "response") {
          this.handleResponse(message as unknown as ResponseMessage);
        }
      });

      socket.addEventListener("close", () => {
        clearTimeout(handshakeTimer);
        this.isClosed = true;
        this.rejectAllPendingRequests(this.describeLostConnection());
        if (!isAuthenticated) {
          reject(new Error(`Could not connect to the Godot editor on port ${this.registration.port}.`));
        }
      });

      socket.addEventListener("error", () => {
        // A "close" event always follows, which does the cleanup.
      });
    });
  }

  /** Sends one request and waits for its answer. Throws EditorRequestError on failure. */
  request<Result = unknown>(
    method: string,
    params: object = {},
    timeoutMilliseconds = DEFAULT_REQUEST_TIMEOUT_MILLISECONDS,
  ): Promise<Result> {
    const socket = this.socket;
    if (!socket || !this.isOpen) {
      return Promise.reject(new Error("Not connected to the Godot editor."));
    }

    const requestId = this.nextRequestId++;
    return new Promise<Result>((resolve, reject) => {
      const timeoutTimer = setTimeout(() => {
        this.pendingRequests.delete(requestId);
        reject(
          new EditorRequestError(
            "TIMEOUT",
            `The Godot editor did not answer '${method}' within ${Math.round(timeoutMilliseconds / 1000)} seconds.`,
            "The editor may be busy (importing, a modal dialog is open, or a script is stuck in a loop). Check with a screenshot.",
          ),
        );
      }, timeoutMilliseconds);

      this.pendingRequests.set(requestId, {
        method,
        resolve: (result) => resolve(result as Result),
        reject,
        timeoutTimer,
      });
      socket.send(JSON.stringify({ type: "request", id: requestId, method, params }));
    });
  }

  close(): void {
    this.isClosed = true;
    // With an explicit code and reason: Godot logs a Unicode error for an empty close frame.
    this.socket?.close(NORMAL_CLOSE_CODE, "Closed by the MCP server");
    this.rejectAllPendingRequests(
      new EditorRequestError(
        "CONNECTION_CLOSED",
        "The connection to the Godot editor was closed by the MCP server.",
      ),
    );
  }

  /** Explains a connection that ended by itself, with what the AI should do next. */
  private describeLostConnection(): EditorRequestError {
    if (isProcessAlive(this.registration.processId)) {
      return new EditorRequestError(
        "EDITOR_DISCONNECTED",
        "The connection to the Godot editor was lost, but the editor is still running.",
        "The addon may have been turned off or reloaded. Try the call again; if it keeps failing, call get_status.",
      );
    }
    return new EditorRequestError(
      "EDITOR_CLOSED",
      "The Godot editor closed or crashed while the request was running.",
      "Tell the person, then call launch_editor to open the project again. Changes that were not saved before the crash are lost; check the result with get_editor_state.",
    );
  }

  private handleResponse(response: ResponseMessage): void {
    const pendingRequest = this.pendingRequests.get(response.id);
    if (!pendingRequest) {
      return;
    }
    this.pendingRequests.delete(response.id);
    clearTimeout(pendingRequest.timeoutTimer);

    if (response.ok) {
      pendingRequest.resolve(response.result);
      return;
    }
    const error = response.error ?? {};
    pendingRequest.reject(
      new EditorRequestError(
        error.code ?? "EDITOR_ERROR",
        error.message ?? `The editor could not run '${pendingRequest.method}'.`,
        error.hint,
        error.details,
      ),
    );
  }

  private rejectAllPendingRequests(error: EditorRequestError): void {
    for (const pendingRequest of this.pendingRequests.values()) {
      clearTimeout(pendingRequest.timeoutTimer);
      pendingRequest.reject(error);
    }
    this.pendingRequests.clear();
  }
}

function parseMessage(data: unknown): Record<string, unknown> | null {
  try {
    const parsed: unknown = JSON.parse(String(data));
    return typeof parsed === "object" && parsed !== null ? (parsed as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}
