# Godot Pilot

**Herhangi bir yapay zekâ asistanının Godot editörünü bir insan gibi kullanmasını sağlayan, bilgisayarında çalışan bir MCP sunucusu.** Editörü görebilir, sahne kurabilir, inspector'dan özellik değiştirebilir, script yazıp kontrol edebilir, oyunu gerçek tuş girdileriyle oynayabilir, hataları okuyup düzeltebilir.

> **Resmi değildir.** Godot Pilot bir topluluk projesidir. Godot Foundation veya Godot Engine projesiyle bir bağı yoktur. "Godot", Godot Foundation'ın markasıdır.

> **Durum: erken geliştirme (0.x).** Kararlı hale gelip gerçek kullanıcılarla test edilmeden 1.0 çıkmayacak.

Ayrıntılar için [İngilizce README](README.md) ve [kurulum rehberi](docs/INSTALL.md).

## Kısaca

- Değişiklikler açık editörde yapılır ve Godot'nun geri alma geçmişine girer, Ctrl+Z ile geri alınır.
- AI editörü, 2D/3D görünümü ve çalışan oyunu görür.
- Oyunu gerçek input ile oynar: tuşu basılı tutma, zamanlama, kare kare ilerletme, "şu olana kadar bekle".
- Kurulu Godot sürümünün kendi dokümantasyonunu ve GDExtension sınıflarını okur.
- Editörün altındaki Godot Pilot paneli AI'ın yaptığı her değişikliği listeler; script, sahne, kaynak ve ayarları istediğin adımdan önceki haline döndürebilir.
- Araçlar gruplar halindedir (20 grupta 120 araç: sahne, inspector, script, animasyon, tilemap, arayüz, 3D, shader, ses, export, oyunu oynama...). AI sadece ihtiyacı olan grupları açar.

## İzin modları

| Mod | AI ne yapabilir |
|---|---|
| `full` (varsayılan) | Açık olan bütün araçları kullanır. |
| `confirm` | Serbestçe bakar. Her değişiklikten önce Godot, AI'ın ne yapmak istediğini gösterir (GDScript ise kodun tamamını), sen İzin ver ya da Reddet dersin. |
| `read-only` | Sadece bakar. Dosya değiştiren, GDScript çalıştıran, oyunu başlatan veya input gönderen araçlar gizlenir. |

Modu AI istemcisine eklerken (`--mode`) ya da Godot'da Godot Pilot panelinden seçebilirsin. İkisi farklıysa sıkı olan geçerlidir. Onay penceresinde bir aracı oturumun sonuna kadar serbest bırakabilirsin; böylece art arda gelen benzer değişiklikler her seferinde sormaz.

## Diller

- **GDScript**: tam destek.
- **C#**: Proje Godot'nun .NET sürümüyle açıldığında AI C# script yazıp düzenleyebilir.
- **GDExtension (Rust, C++)**: AI, eklentilerinin eklediği sınıfları, özellikleriyle, metotlarıyla ve sinyalleriyle görür.

Uçtan uca testler şu an bir GDScript projesiyle yapılıyor.

## Gizlilik

Godot Pilot senin bilgisayarında çalışır ve hiçbir yere veri göndermez: hesap yok, bulut yok, **veri toplama yok**.

AI istemcin ise ayrı bir konu: AI'ın Godot Pilot üzerinden okuduğu her şey (kod, sahneler, ekran görüntüleri, hatalar) kullandığın AI modeline, o sağlayıcının kurallarıyla gider. Her şeyin bilgisayarında kalması için modelin de kendi bilgisayarında çalışması gerekir.

Godot 4.5 veya üstü gerekir. Her değişiklik Godot 4.5.2, 4.6.3 ve 4.7.2 ile test edilir.

## Lisans

[GNU AGPL-3.0](LICENSE). Kullanabilir, inceleyebilir, değiştirebilir, paylaşabilirsin. Değiştirilmiş bir sürümü dağıtır veya internet üzerinden sunarsan kaynak kodunu aynı lisansla paylaşmak zorundasın.

**Godot Pilot ile yaptığın oyunlar bu lisanstan etkilenmez.** Addon sadece editörde çalışır, export edilen oyuna girmez; oyununu istediğin lisansla satabilirsin.
