# KindleWall

Kindle alıntılarını macOS masaüstü duvar kağıdına dönüştürür.

KindleWall'a Kindle'ındaki `My Clippings.txt` dosyasını göster; kendi kütüphanenden bir pasajı
masaüstüne basar ve senin belirlediğin aralıkla değiştirir.

![KindleWall](docs/screenshots/main.png)

## Kurulum

```sh
brew tap bekircem/tap
brew trust bekircem/tap      # Homebrew 6 üçüncü taraf tap'ler için bunu istiyor
brew install --cask kindlewall
```

Ya da imzalı ve notarize edilmiş DMG'yi
[Releases](https://github.com/bekircem/KindleWall/releases/latest) sayfasından indir.

**macOS 26 (Tahoe) veya üstü gerekir.**

## Ne yapar

- **Alıntılarını okur.** `My Clippings.txt` dosyasını hem İngilizce hem Türkçe Kindle
  biçiminde ayrıştırır, içeriğe göre yinelenenleri ayıklar, yer imlerini ve notları eler.
- **Altı stil** — Gece, Kağıt, Izgara, Şafak, Derinlik, Orman Işığı — punto her pasaja göre
  hesaplanır, sabit bir kutuya sığdırılıp kırpılmaz.
- **Güneşi izleyen duvar kağıdı.** İstersen renk sıcaklığı güneşin konumunu takip eden dinamik
  bir HEIC yazar; aynı pasaj gün boyunca ısınır ve soğur.
- **Döngü senin denetiminde.** Tüm kitaplar, kitap kitap, yalnızca sabitlenenler ya da yalnızca
  favoriler — 30 dakikadan günlüğe, ya da özel bir aralık. Havuz tükenene kadar tekrarsız
  karıştırır.
- **Her yerden alıntı yakala.** Genel kısayol ya da Servisler menüsü, herhangi bir uygulamada
  seçtiğin metni alıntıya çevirir.
- **Menü çubuğunda yaşar**; pencereyi kapatınca çalışmaya devam eder.
- **Mac'lerin arasında eşitlenir** — kendi özel iCloud veritabanın üzerinden, isteğe bağlı ve
  iCloud'a giriş yapmadıysan kapalı.
- **Kendini günceller** — Sparkle ile, EdDSA imzalı sürümler.

## Yol haritası

- İngilizce arayüz (1.1)

## Kaynaktan derleme

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project KindleWall.xcodeproj -scheme KindleWall -configuration Debug build
```

Testler bilerek iki adımlı — tek adımlı `xcodebuild test` test paketini hazırlamaz ve test
başarısızlığı gibi görünen ama aslında testlerin hiç koşmadığı anlamına gelen bir hata verir:

```sh
xcodebuild -project KindleWall.xcodeproj -scheme KindleWall clean
xcodebuild build-for-testing -project KindleWall.xcodeproj -scheme KindleWall -destination 'platform=macOS,arch=arm64'
xcodebuild test-without-building -project KindleWall.xcodeproj -scheme KindleWall -destination 'platform=macOS,arch=arm64'
```

Bir sonuca inanmadan önce her zaman `Executed N tests` satırını oku.

Uygulama Swift 6 dil kipinde ve `SWIFT_STRICT_CONCURRENCY: complete` ile derleniyor; izolasyon
ihlalleri uyarı değil derleme hatası.

## Gizlilik

Analitik yok, telemetri yok, bu projenin işlettiği bir sunucu yok. Mac'inden neyin çıkıp
neyin çıkmadığı tam olarak şöyle:

| | Nereye gider |
|---|---|
| Alıntıların | Hiçbir yere — iCloud'a giriş yaptıysan **kendi** özel CloudKit veritabanına, başka hiçbir yere |
| **Kitap adların** | Kütüphane ekranı kapak görseli ararken, arama sorgusu olarak Google Books ve Open Library'ye |
| Güncelleme denetimi | Appcast'i okumak için GitHub'a |

Kapak araması açıkça söylenmeyi hak ediyor: kütüphaneyi açmak kitaplarının adlarını iki üçüncü
taraf servise gönderir. Yanına senin hakkında başka hiçbir şey eklenmez, ama adların kendisi ne
okuduğun hakkında bir şey söyler.

## Lisans

[GPL-3.0](LICENSE)

## Marka

KindleWall'ın Amazon ile bir bağlantısı yoktur; Amazon tarafından desteklenmez veya
onaylanmaz. Kindle, Amazon.com, Inc. şirketinin tescilli markasıdır.

---

🇬🇧 [English README](README.md)
