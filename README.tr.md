# Godot Pilot

**Herhangi bir yapay zekâ asistanının Godot editörünü bir insan gibi kullanmasını sağlayan, bilgisayarında çalışan bir MCP sunucusu.** Editörü görebilir, sahne kurabilir, inspector'dan özellik değiştirebilir, script yazıp kontrol edebilir, oyunu gerçek tuş girdileriyle oynayabilir, hataları okuyup düzeltebilir.

> **Resmi değildir.** Godot Pilot bir topluluk projesidir. Godot Foundation veya Godot Engine projesiyle bir bağı yoktur. "Godot", Godot Foundation'ın markasıdır.

> **Durum: erken geliştirme (0.x).** Kararlı hale gelip gerçek kullanıcılarla test edilmeden 1.0 çıkmayacak.

Ayrıntılar için [İngilizce README](README.md) ve [kurulum rehberi](docs/INSTALL.md).

## Kısaca

- Değişiklikler canlı editörde yapılır, Ctrl+Z ile geri alınır.
- AI editörü, 2D/3D görünümü ve oyunu görür.
- Oyunu gerçek input ile oynar: tuşu basılı tutma, zamanlama, kare kare ilerletme.
- Kurulu Godot sürümünün kendi dokümantasyonunu okur; API uydurmaz.
- Araçlar gruplar halindedir (20 grupta 118 araç: sahne, inspector, script, animasyon, tilemap, arayüz, 3D, shader, ses, export, oyunu oynama...), AI ihtiyacı olanı açıp kapatır; bağlam şişmez.
- İzin modları: `full`, `confirm` (her değişiklikten önce Godot'ta İzin ver / Reddet), `read-only`.
- GDScript, C# ve GDExtension (Rust, C++) projeleriyle çalışır.
- Her şey senin bilgisayarında çalışır. Hesap yok, bulut yok, **veri toplama yok**.

## Lisans

[GNU AGPL-3.0](LICENSE). Kullanabilir, inceleyebilir, değiştirebilir, paylaşabilirsin. Değiştirilmiş bir sürümü dağıtır veya internet üzerinden sunarsan kaynak kodunu aynı lisansla paylaşmak zorundasın.

**Godot Pilot ile yaptığın oyunlar bu lisanstan etkilenmez.** Addon sadece editörde çalışır, export edilen oyuna girmez; oyununu istediğin lisansla satabilirsin.
