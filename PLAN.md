# OpenRelax uçtan uca geliştirme planı

Kapsam: mevcut kaynak sürümünün güvenliği, sonuç doğruluğu, açık kaynak bakımı ve arayüzü.
Kaynak başlangıcı: `a9750d4`; çalışma dalı: `codex/openrelax-safety-and-oss-20261009`.
MIT lisansı ve kaynak dağıtımı korunur. Kaynak değişiklikleri çalışma dalı/PR ile
GitHub incelemesine gönderilir; kesin CI durumu PR kontrollerinden doğrulanır.
Gerçek SYSTEM kurulumu ve kişisel/sistem verilerinde temizlik bu yerel kabulün parçası değildir.

| Sıra | İş | Kabul kriteri | Durum |
| --- | --- | --- | --- |
| 1 | Test izolasyonu ve başlangıç görselleri | Dört görünüm × TR/EN; yeni owned fixture, açık state/cache/output sınırı | Tamamlandı |
| 2 | Fotokapan yetki ve gizlilik sınırı | Admin owner/protected ACL, çağıran kullanıcı RX; farklı admin hesabına ReaderSid aktarımı; atomik code deploy; reparse/hardlink reddi; başarısız upgrade disabled; argüman/ham Defender kaynak kaydı kapalı | Kod ve kontratlar tamamlandı; gerçek elevated kurulum sürüm kapısı |
| 3 | Ayarlar ve yıkıcı işlem güvenliği | Tip doğrulama, atomik kayıt, global erişim kontrollü mutex; SelfTest/AutoClean çakışması reddedilir; bozuk ayarda AutoClean durur; sepet kapalı; bakım onayı; TEMP/reparse koruması | Tamamlandı |
| 4 | Ortak bakım sonucu ve otomasyon | GUI/headless ortak işleyici; başarı/kısmi/hata ve exit kodu; hizmet geri başlatma hatasında tamamlanan silme sayısı korunur; çıkış aktif işin bitmesini bekler; tercih kaydı/rollback | Kod ve izole kabul tamamlandı |
| 5 | RAM ve CPU teşhis doğruluğu | RAM/DNS ayrı opt-in; signed geçici net bellek değişimi; atanmayan CPU sürücü diye sunulmaz; teşhis kesin neden iddiası taşımaz | Tamamlandı |
| 6 | Görsel ve erişilebilir kullanım | Görsel sırayla TabIndex, yerelleştirilmiş accessible adlar, native checkbox/focus; WorkingArea sığdırma ve küçük pencerede kaydırma; TR/EN incelemesi | Native kontrol API/540×450 viewport ve 8 render kabulü tamamlandı; fiziksel klavye, gerçek DPI geçişi ve Narrator konuşması sürüm kapısı |
| 7 | Açık kaynak işbirliği ve CI | SECURITY/conduct, issue/PR şablonları, CODEOWNERS, destek sınırı/yayın checklist; parser/kontrat, küçük motor, native UI/çıkış/render kontrolleri CI işinde | Kaynaklar ve yerel giriş noktaları tamamlandı; remote CI sonucu PR kontrollerinde; repo policy kararı ayrı |
| 8 | Uçtan uca kabul | Gerçek izole SelfTest/AutoClean, scan/disk worker, küçük motor fixture, GUI/resource kontrolü, 8 gerçek render ve bağımsız review | Yerel kabul tamamlandı |

## Açık kaynak değerlendirmesi

Başlangıçta MIT lisansı, katkı rehberi, SHA ile sabitlenmiş checkout ve read-only CI izinleri vardı.
Ancak açık kaynak olma iddiasını güvenilir bakım sürecine bağlayan güvenlik bildirimi,
destek kapsamı, yapılandırılmış katkı akışı ve kritik güvenlik regresyonları eksikti.
Bunlar SECURITY.md, CODE_OF_CONDUCT.md, issue/PR şablonları, CODEOWNERS,
CONTRIBUTING.md sürüm kontrol listesi ve genişletilmiş verify ile giderildi.
Süre taahhüdü bulunmayan güncel LTS iddiası kaldırıldı. Yeni güvenlik politikası özel
bildirim özelliğini etkinleştirmez; CODEOWNERS zorunlu review/branch protection kurmaz.
Bu GitHub ayarları, remote CI, tag/release ve varsa imzalı binary ayrı sürüm kapılarıdır.

Ayarlar, yol korumaları ve bakım koordinasyonu bağımsız `lib/OpenRelax.Core.ps1` içine
alındı. Arayüz/target discovery hâlâ büyük bir dosyadadır; yeni özelliklerden önce
daha fazla modül çıkarımı değerlendirilebilir. Bu yerel güvenlik çalışmasına yeni SDK,
ürün özelliği, model veya ağır test bağımlılığı eklenmedi.

## Yerel kabul kanıtları — 9 Ekim 2026

- Windows PowerShell 5.1: 12 PS kaynak/test dosyası ve 4 worker metni parser temiz.
- `tests/verify.ps1`: 17/17 StrictMode güvenlik kontratı; farklı-account ReaderSid
  korunur; gerçek SelfTest state/target
  değiştirmez; bozuk AutoClean durur; doğru eski fixture dosyası/count/bytes/stats;
  restricted headless iş exit 2; gerçek scan/disk worker ve junction state reddi.
  SelfTest+AutoClean birlikte verilirse nonzero exit ve dosya/ayar/log değişmemesi.
- Windows Update kontratı: başlangıç Running/Stopped, paused/pending reddi,
  stop/stop sonrası hata/no-op, deletion ve restart/no-op hataları; gerçek servis çalıştırılmadı.
- Küçük engine: 24 grid + 6 özel dosya ve uzun yol; worker, sentinel, junction,
  kilitli/yeni dosya ve staging koruması geçti.
- GUI: 30 tur/10 scan/2 launch; GDI 54→54, USER 132→130; sınırlar içinde handle/bellek.
  Son klavye/viewport düzeltmesinden sonra 18 tur/6 başarılı scan/1 launch,
  GDI 56→56, handle 930→920, bellek 145→118 MB geçti.
- `tests/ui-smoke.ps1`: native settings focus sırası, TR/EN accessible adlar,
  checkbox default action/tercih persistence ve 540×450 viewportta görünür erişim.
- Fotokapan gerçek kontrollü CPU yükü: 2 burst × 6 saniye/9 worker, 2 start/end,
  18 kontrolün tümü geçti; argümanlar yok; recorder maliyeti tek çekirdeğin %1,2'si,
  handle 795→870 ve bellek 89→103 MB. Çocuklar owned TEMP/module-cache ve
  bounded/finally kapatması kullanır; okuyucu bozuk/yarım satırları atlar.
- `tests/exit-smoke.ps1`: gerçek GUI kapanış isteği aktif sentetik worker'ın
  tamamlanmasını bekledi; worker begin/end kanıtı korundu.
- Görsel: dört sayfa × TR/EN, 8 gerçek WinForms PNG; dolu Fotokapan fixture da incelendi.
  Kesilen durum/Duration, düşük kontrast, karışık dil, siyah başlık/beyaz filler ve
  gereksiz yatay kaydırma düzeltildi. Üç salt-okunur yardımcı review bulguları ele alındı.

## Doğrulama sınırı

Gerçek kullanıcı profili, sepet, servisler ve kurulu görevler üzerinde yıkıcı test yapılmaz.
Motor testleri yalnız yeni, sahibi doğrulanan sentetik çalışma alanlarında silme yapar.
Computer Use bu tur başladı, fakat envanter OpenRelax test penceresini hedef olarak
döndürmedi; dış klavye otomasyonu uygulanmadı. Görsel kabul gerçek WinForms test
yakalamaları, erişilebilir kontrol kabulü native API ile yapılır. Test edilmemiş Windows yapılandırmaları ve yarış
koşulları kesin güvenlik garantisi olarak sunulmaz.

Yayın öncesi sırayla: (1) disposable Windows'ta SYSTEM install/upgrade/uninstall ve
effective ACL; (2) gerçek Windows Update restorasyonu; (3) klavye/high DPI/screen reader
ve desteklenen Windows build'leri; (4) ayrı RDP/session kullanımının native doğrulaması;
(5) GitHub özel güvenlik bildirimi/required review kararı ve PR'da remote CI;
(6) sürüm/changelog ve tam source archive kontrolü sonrası yetkili kararlı sürüm yayını.
İmzalı dağıtım ve LTS taahhüdü ancak gerçek süreçleri kurulunca duyurulmalıdır.
