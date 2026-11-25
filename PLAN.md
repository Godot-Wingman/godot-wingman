# Godot MCP — Proje Planı

## Hedef

Herhangi bir AI istemcisinin (Claude, Cursor, Codex, …) Godot'u bir insan gibi kullanmasını sağlamak. AI şunları yapabilmeli:

- **Görmek:** Editörü ve oyunu görebilmeli.
- **Editörde çalışmak:** Sahne kurabilmeli, inspector'dan özellik değiştirebilmeli, script yazabilmeli, animasyon yapabilmeli.
- **Oynamak:** Oyunu gerçekten oynayabilmeli. Tek bir tuş basıp ekran görüntüsü almak bu sayılmaz.
- **Düzeltmek:** Hatayı okuyup düzeltebilmeli.

Her şey lokal çalışır. Bulut sunucusu, hesap ya da API anahtarı gerekmez. Proje tamamen açık kaynaktır.

## Mevcut MCP'lerin eksikleri (çözeceğimiz şeyler)

| Sorun         | Mevcutlarda                                                                                                                    | Bizde                                                                                                      |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------- |
| Değişiklikler | Dosyalar headless Godot ile yazılıyor. Açık editöre yansımıyor, Ctrl+Z yok. Her işlem yeni bir Godot süreci açtığı için yavaş. | Değişiklik canlı editörde yapılır. Anında görünür ve Ctrl+Z ile geri alınır.                               |
| Görme         | Sadece oyunun ekran görüntüsü alınabiliyor.                                                                                    | Editörün 2D/3D viewport'u da görünür. Kamera düğüme odaklanır, açı değiştirilir.                           |
| Oynama        | Tek seferlik tuş basımı (yalandan oynama).                                                                                     | Gerçek input olayları: basılı tutma, süre ve sıra. Frame frame ilerletme ve "şu olana kadar bekle" komutu. |
| Kapsam        | Bir MCP'de olan diğerinde yok. Hiçbiri animasyon, TileMap, UI ya da shader gibi alanları adam akıllı kapsamıyor.               | Godot'un her alanı için ayrı bir araç grubu var. Gruplar aç/kapa yapılır.                                  |
| API bilgisi   | Yok. AI eski ya da var olmayan API'ler uyduruyor.                                                                              | Çalışan motorun kendi API'si ve dokümantasyonu sorgulanabilir.                                             |
| Eksik araç    | Araç yoksa iş yapılamıyor.                                                                                                     | Kaçış kapısı var: editörde ve oyunda doğrudan GDScript çalıştırılır (Blender MCP'deki gibi).               |

## Mimari

```
AI istemcisi ──stdio──▶ MCP sunucusu (TypeScript + Bun, tek çalıştırılabilir dosya)
                              │  WebSocket, sadece 127.0.0.1 + token
                              ▼
                        Godot editörü içindeki addon (GDScript)
                              │  Godot'un kendi debugger kanalı
                              ▼
                        Çalışan oyun (runtime köprüsü, sadece editörden başlatınca)
```

- Model, Blender MCP ile aynı: lokal bir sunucu ve uygulamanın içinde çalışan bir addon. Kullanıcı addon'u elle kurmaz, sunucu projeye kendisi kurar.
- Editör kapalıysa sunucu Godot editörünü kendisi açar.
- **Oyun bağlantısı Godot'un kendi debugger kanalından geçer** (`EditorDebuggerPlugin` + `EngineDebugger`):
  - Ekstra port açılmaz.
  - Editördeki Play tuşuyla başlatılan oyunda da çalışır.
  - Export edilmiş oyuna hiçbir şey girmez.
- **Neden TypeScript + Bun (Node/npm değil):**
  - Resmi MCP SDK'sı TypeScript'te ve Bun üzerinde çalışır.
  - **Kullanıcıya tek bir dosya veririz.** `bun build --compile` her işletim sistemi için tek bir çalıştırılabilir dosya üretir (`godot-pilot.exe` gibi). Kullanıcının Node, npm ya da Bun kurmasına gerek yoktur. GitHub Releases'tan indirir ve MCP ayarına dosyanın yolunu yazar.
  - Windows, macOS ve Linux dosyaları tek bilgisayardan üretilir.
  - Bun'ın kendi test aracı ve paketleyicisi vardır. Ekstra araç yığını gerekmez.
  - Ağır iş zaten Godot tarafında, o yüzden Rust'ın hızı burada fark yaratmaz.
- **Neden GDScript addon (GDExtension değil):** Derleme gerekmez ve her Godot 4.x sürümünde çalışır.

## Sürümden bağımsızlık

- Sınıf, özellik ve metot listeleri kodda sabit tutulmaz. Hepsi çalışan motordan `ClassDB` ile okunur.
- API dokümantasyonu kurulu Godot'un kendisinden alınır (`--dump-extension-api-with-docs`) ve sürüm başına önbelleğe yazılır. Godot güncellenince doküman da kendiliğinden güncellenir.
- Sürüm farkları sürüm numarasına bakılarak değil, özellik algılamayla ele alınır (`has_method`, `ClassDB.class_exists`).
- Geliştirme ve test Godot 4.7.2 üzerinde yapılır.

## Araç grupları (aç/kapa)

Toplamda yaklaşık **130–150 araç** olur. Hepsi aynı anda açık olursa AI'ın bağlamı dolar, o yüzden araçlar gruplara ayrılır:

- **`core` grubu her zaman açıktır.** Bu grupta grupları listeleme, açma ve kapama araçları da vardır.
- **Grupları AI kendisi açıp kapatır.** Örneğin animasyon yapması gerekince `animation` grubunu açar, işi bitince kapatır. Sunucu bunu MCP'nin `tools/list_changed` bildirimiyle istemciye anında haber verir.
- **Varsayılan açık gruplar:** `core`, `scene`, `inspector`, `script`, `project`. Bunlar toplam yaklaşık 45 araç eder.
- **Hazır profiller** birden çok grubu tek seferde açar:
  - `edit`: editör işleri.
  - `play`: oyunu oynama ve test.
  - `all`: her şey.
- **Hangi grupların açılışta açık olacağı ayardan seçilebilir.** Araç listesinin anlık değişmesini desteklemeyen istemciler de böylece çalışır.

| Grup           | Ne işe yarar                                              | Örnek araçlar                                                                                                      | ~Araç |
| -------------- | --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ | ----- |
| `core`         | Bağlantı, grupları yönetme, kaçış kapısı, loglar, doküman | `get_status`, `toggle_toolsets`, `execute_editor_script`, `get_errors`, `take_editor_screenshot`, `get_class_docs` | 10    |
| `scene`        | Sahneler ve düğüm ağacı                                   | `open_scene`, `get_scene_tree`, `add_node`, `move_node`, `instance_scene`, `select_nodes`, `batch_edit`            | 12    |
| `inspector`    | Özellikler, gruplar, metadata                             | `get_properties`, `set_properties`, `reset_property`, `set_groups`                                                 | 6     |
| `script`       | Script yazma, düzenleme, hata kontrolü                    | `create_script`, `edit_script`, `attach_script`, `validate_script`, `find_usages`                                  | 8     |
| `project`      | Proje ayarları, input map, autoload, eklentiler           | `set_project_setting`, `add_input_action`, `add_autoload`, `set_layer_names`                                       | 8     |
| `signals`      | Sinyal bağlama                                            | `list_signals`, `connect_signal`, `disconnect_signal`                                                              | 4     |
| `resources`    | Materyal, tema, StyleBox, genel resource                  | `create_resource`, `edit_resource`, `create_material`, `edit_theme`                                                | 8     |
| `filesystem`   | Dosyalar, import, bağımlılık                              | `move_file` (referansları bozmadan), `search_files`, `get_dependencies`, `reimport`                                | 7     |
| `viewport`     | Editör kamerası ve görüntü                                | `focus_node`, `orbit_camera`, `set_view`, `screenshot_node`                                                        | 6     |
| `play`         | Oyunu çalıştırma ve zaman kontrolü                        | `run_game`, `stop_game`, `pause_game`, `step_frames`, `wait_until`                                                 | 6     |
| `input`        | Gerçek oyuncu girdisi                                     | `press_key`, `hold_action`, `mouse_click`, `mouse_drag`, `input_sequence`, `type_text`                             | 6     |
| `game_inspect` | Çalışan oyunu inceleme ve değiştirme                      | `get_game_tree`, `set_game_property`, `call_game_method`, `execute_game_script`, `capture_frames`                  | 7     |
| `debug`        | Performans ve hata ayıklama                               | `get_performance`, `start_profiler`, `set_breakpoint`, `get_stack`                                                 | 5     |
| `animation`    | AnimationPlayer ve AnimationTree                          | `create_animation`, `add_track`, `insert_keyframe`, `edit_state_machine`, `preview_animation`                      | 10    |
| `tilemap`      | TileSet ve TileMapLayer                                   | `create_tileset_from_texture`, `paint_cells`, `fill_rect`, `paint_terrain`                                         | 6     |
| `ui`           | Control düğümleri ve düzen                                | `set_anchor_preset`, `arrange_container`, `set_theme_override`, `set_focus_neighbors`                              | 6     |
| `3d`           | 3D sahne kurma                                            | `import_model`, `add_light`, `set_environment`, `bake_navigation`, `add_collision_shape`                           | 7     |
| `shader`       | Shader yazma ve deneme                                    | `create_shader`, `edit_shader`, `get_shader_errors`, `set_shader_parameter`                                        | 4     |
| `audio`        | Ses yolları ve oynatıcılar                                | `edit_audio_bus`, `add_audio_player`                                                                               | 3     |
| `export`       | Build alma                                                | `list_export_presets`, `export_project`, `check_export_templates`                                                  | 4     |

Grup ve araç listesi fazlar ilerledikçe netleşecek. Tablo, hedeflenen kapsamı gösteriyor.

## Araç tasarımı ilkeleri

- **Az token, net çıktı:** Kompakt çıktı, filtre ve sayfalama. Büyük sahne ağaçları derinlik sınırıyla döner.
- **Her editör değişikliği `EditorUndoRedoManager` üzerinden yapılır.** Kullanıcı Ctrl+Z ile geri alabilir.
- **Toplu işlem:** Tek çağrıda birden çok değişiklik yapılabilir, böylece gidiş-dönüş sayısı azalır.
- **Düzeltilebilir hata mesajları:** Her hata neyin yanlış olduğunu ve doğru kullanımı söyler.
- **Tip dönüşümü otomatiktir.** `Vector2`, `Color`, `NodePath`, `Resource` yolu gibi değerler JSON'dan doğru Godot tipine çevrilir.
- **Her aracın açıklaması AI için yazılır:** ne zaman kullanılır, ne döner ve bir örnek.

## Kod yazım kuralları

Kod, temel JavaScript/React bilen birinin okuyup anlayabileceği şekilde yazılır.

- **İsimler açıklayıcıdır.** Tek harfli ya da kısaltılmış isim kullanılmaz:
  - `n`, `t`, `cb`, `res` değil, `node`, `elapsedSeconds`, `onComplete`, `response`.
  - Döngü sayaçları da anlamlı isim alır: `for (const node of selectedNodes)`.
- **Matematik ve formüllerde de anlamlı isimler kullanılır:** `distanceToTarget`, `cameraOrbitAngle`.
- **Fonksiyonlar kısa ve tek işlidir.** Uzun fonksiyonlar adı konmuş parçalara bölünür.
- **Yorumlar "neden"i açıklar.** Kodun ne yaptığını tekrar etmez.
- **Her dosyanın başında** o dosyanın ne işe yaradığını anlatan kısa bir açıklama bulunur.
- **TypeScript `strict` modda çalışır.** `any` kullanılmaz. Biçimlendirme ve lint Biome ile yapılır (tek araç, çok hızlı).
- **GDScript tarafında statik tipler kullanılır** (`var speed: float`). Godot'un isimlendirme kuralları (`snake_case`) uygulanır.
- **Kod ve yorumlar İngilizcedir**, çünkü proje uluslararası. README hem İngilizce hem Türkçe olur.

## Yetenekler

Ayrıntılı liste için yukarıdaki grup tablosuna bakın. Öne çıkanlar:

- **Görmek:**
  - Editör viewport'u ve oyun görüntüsü.
  - Seri kareler, böylece hareket görülebilir.
  - Hatalar dosya:satır bilgisi ve stack trace ile gelir.
- **Editörde:**
  - Inspector'daki her özellik okunur ve yazılır.
  - Script hataları editörün kendi parser'ıyla anında kontrol edilir.
  - Dosyalar referanslar bozulmadan taşınır.
- **Oynamak:**
  - Gerçek input olayları (`Input.parse_input_event`).
  - Oyunu duraklatıp frame frame ilerletme.
  - `wait_until("player.is_on_floor()")` gibi koşulla bekleme.
  - Çalışan oyunu canlı inceleme.
- **Bilgi:**
  - Kurulu motor sürümünün API'si ve açıklamaları.
  - Proje içinde arama.

## Fazlar

**Faz 1 — Temel ve kaçış kapısı** ✅ (26 Kasım 2026)

- Repo, TypeScript + Bun sunucu ve addon.
- WebSocket protokolü: el sıkışma, token, kopunca yeniden bağlanma.
- **Araç grubu sistemi** (aç/kapa, profiller, ayar dosyası).
- Addon'un projeye otomatik kurulması ve Godot'un sunucu tarafından başlatılması.
- `core` grubu: editörde GDScript çalıştırma, API ve doküman araçları, log ve hata okuma, editör ekran görüntüsü.

_Sonuç:_ AI editörü görür ve script ile her şeyi yapabilir.

**Faz 2 — Editörde insan gibi** ✅ (26 Kasım 2026)

- Gruplar: `scene`, `inspector`, `script`, `project`, `signals`, `resources`, `filesystem`, `viewport`.
- UndoRedo ve toplu işlem.

**Faz 3 — Oyunu gerçekten oynamak** ✅ (26 Kasım 2026)

- Debugger köprüsü.
- Gruplar: `play`, `input`, `game_inspect`, `debug`.

**Faz 4 — Özel editörler ve yayın**

- Gruplar: `animation`, `tilemap`, `ui`, `3d`, `shader`, `audio`, `export`.
- Token optimizasyonu ve testler.
- README (EN/TR).
- GitHub Releases'ta her işletim sistemi için tek dosya.

Her fazın sonunda `test-project/` içindeki küçük bir oyun üzerinde AI ile uçtan uca deneme yapılır. Bir sonraki faza bu deneme geçmeden geçilmez.

## Repo yapısı

```
server/         TypeScript + Bun MCP sunucusu
addon/          addons/godot_mcp/ — editör eklentisi + runtime köprüsü
test-project/   deneme Godot projesi
docs/
```

## Güvenlik

- Sunucu sadece `127.0.0.1` adresini dinler. Her oturumda rastgele bir token üretilir, böylece başka uygulamalar bağlanamaz.
- Runtime köprüsü sadece editörden başlatılan oyunda açılır. Export edilen oyuna girmez.

## Lisans

Hedef: Herkes kullanabilir, fork'layabilir, değiştirebilir ve PR açabilir. Kimse kodu alıp kapalı, paralı bir ürüne çeviremez.

- **Karar: AGPL-3.0.** Dağıtılan her kopya ve değiştirilmiş sürüm aynı lisansla, kaynak koduyla birlikte verilmek zorundadır. İnternette hizmet olarak sunan da kaynak kodunu paylaşmak zorundadır.
- **Addon, oyunun export'una hiçbir zaman girmez.** Bu yüzden bu MCP ile yapılan oyunlar lisanstan etkilenmez, geliştirici oyununu istediği gibi satabilir. README'de açıkça yazılacak.

## Açık kararlar

- **Proje adı.** Aday: `godot-pilot`.
