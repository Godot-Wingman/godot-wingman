/**
 * Decides which Godot editor the tools talk to, and keeps the connections open.
 *
 * - One editor running: it is used automatically.
 * - Several editors running: the one chosen with select_editor (or launch_editor) is
 *   used; without a choice the tool fails and lists the editors to choose from.
 * - A broken connection is reopened on the next request.
 */
import { normalizePathForComparison } from "../paths.ts";
import {
  DEFAULT_REQUEST_TIMEOUT_MILLISECONDS,
  EditorConnection,
  EditorRequestError,
} from "./editor-connection.ts";
import {
  type EditorRegistration,
  findRegistrationForProject,
  readEditorRegistrations,
} from "./editor-registry.ts";

export class EditorManager {
  /** Open connections, keyed by the editor's process id. */
  private readonly connectionsByProcessId = new Map<number, EditorConnection>();
  private selectedProjectPath: string | null = null;

  listEditors(): Promise<EditorRegistration[]> {
    return readEditorRegistrations();
  }

  get selectedProject(): string | null {
    return this.selectedProjectPath;
  }

  selectProject(projectPath: string | null): void {
    this.selectedProjectPath = projectPath;
  }

  /** Returns an open, authenticated connection to the editor the tools should use. */
  async getConnection(): Promise<EditorConnection> {
    const registration = await this.chooseEditor();
    const existingConnection = this.connectionsByProcessId.get(registration.processId);
    if (existingConnection?.isOpen) {
      return existingConnection;
    }

    existingConnection?.close();
    const connection = new EditorConnection(registration);
    await connection.open();
    this.connectionsByProcessId.set(registration.processId, connection);
    return connection;
  }

  async request<Result = unknown>(
    method: string,
    params: object = {},
    timeoutMilliseconds = DEFAULT_REQUEST_TIMEOUT_MILLISECONDS,
  ): Promise<Result> {
    const connection = await this.getConnection();
    return connection.request<Result>(method, params, timeoutMilliseconds);
  }

  /** The registry entry of the editor the tools use (project folder, Godot executable...). */
  getActiveRegistration(): Promise<EditorRegistration> {
    return this.chooseEditor();
  }

  closeAll(): void {
    for (const connection of this.connectionsByProcessId.values()) {
      connection.close();
    }
    this.connectionsByProcessId.clear();
  }

  private async chooseEditor(): Promise<EditorRegistration> {
    const registrations = await readEditorRegistrations();

    if (this.selectedProjectPath) {
      const selectedRegistration = findRegistrationForProject(registrations, this.selectedProjectPath);
      if (selectedRegistration) {
        return selectedRegistration;
      }
      throw new EditorRequestError(
        "SELECTED_EDITOR_NOT_RUNNING",
        `No Godot editor with the addon is running for the selected project '${this.selectedProjectPath}'.`,
        "Start it with launch_editor, or pick another running editor with select_editor.",
      );
    }

    const [onlyRegistration] = registrations;
    if (registrations.length === 1 && onlyRegistration) {
      return onlyRegistration;
    }

    if (registrations.length === 0) {
      throw new EditorRequestError(
        "NO_EDITOR_RUNNING",
        "No Godot editor with the Godot Pilot addon is running.",
        "Call launch_editor with the project folder. It installs the addon if needed and opens the editor.",
      );
    }

    const editorList = registrations
      .map((registration) => `- ${registration.projectName} (${registration.projectPath})`)
      .join("\n");
    throw new EditorRequestError(
      "SEVERAL_EDITORS_RUNNING",
      `Several Godot editors are running:\n${editorList}`,
      "Call select_editor with the project path of the one to use.",
    );
  }
}

export function isSameProject(firstPath: string, secondPath: string): boolean {
  return normalizePathForComparison(firstPath) === normalizePathForComparison(secondPath);
}
