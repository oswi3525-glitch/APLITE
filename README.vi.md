> **APLite (AirPlayLite)** là dự án phát triển độc lập dựa trên iDesk gốc của itshieuk: https://github.com/itshieuk/iDesk. APLite không phải bản phát hành chính thức hay được xác nhận bởi dự án iDesk gốc. Xem [README.md](README.md) để biết các thay đổi và hướng dẫn build của APLite.

# iDesk — tài liệu gốc (xem phần ghi nhận APLite ở đầu)

**Chế độ máy tính cho iPhone và iPad.** Cắm vào màn hình hoặc TV (hoặc phản chiếu lên Apple TV qua AirPlay): màn hình
lớn có desktop với cửa sổ, thanh tác vụ, menu ứng dụng, trang web bản máy tính và app iOS chạy trong cửa sổ. iPhone
hoặc iPad thành trackpad và bàn phím.

[English](README.md)

> **Thử nghiệm.** iDesk dùng API riêng của UIKit, cài bằng cách sideload, và bản iOS sau có thể làm hỏng vài phần.

## Tính năng

- **Spotlight** (⌘ + Space hoặc nút kính lúp trên thanh tác vụ): tìm app, cửa sổ đang mở, file, dấu trang và lịch sử
  trong một ô, kèm tính toán (`(12+3)*4`, `15% of 80`) và đổi đơn vị (`5 km to mi`, `100 f to c`).
- **Cửa sổ** kéo, đổi cỡ, thu nhỏ, phóng to. Kéo lên mép trên để chọn bố cục (nửa, một phần ba, một phần tư); khi một
  cửa sổ đã chiếm một bên, iDesk gợi ý các cửa sổ khác để lấp phần còn lại. ⌘ + mũi tên cũng ghép được. Giữ một cửa
  sổ luôn ở trên cùng từ menu thanh tiêu đề. Thanh tác vụ có App gần đây, Màn hình chính và Quay lại; menu ứng dụng có
  tìm kiếm và hàng Gần đây; ⌥ + Tab, ⌘ + Q / H / `; nhiều màn hình ảo và góc nóng (tùy chọn). Cửa sổ đang mở được mở
  lại ở lần sau.
- **Lịch sử clipboard** (⌘ + Shift + V): những gì bạn đã sao chép trên desktop, mục đã ghim lên đầu.
- **Chụp màn hình** cả màn hình (⌘ + Shift + 3) hoặc một vùng, một cửa sổ (⌘ + Shift + 4): lưu vào Ảnh và Tệp, sao
  chép sẵn, hiện ảnh nhỏ ở góc. **Ghi chú dán** trên desktop (chuột phải vào desktop).
- **Trình duyệt** có tab, trang bản máy tính, cửa sổ đăng nhập, video toàn màn hình, tìm trong trang, phóng to, thanh
  dấu trang và lịch sử, chặn quảng cáo và theo dõi với danh sách chặn / cho phép riêng, thanh âm lượng dùng được cho video web, chỉnh cỡ chữ cho mọi trang, trang web tối, dịch trang, chế độ đọc và
  đọc to. Cài trang web thành app (cửa sổ và icon riêng), tách video thành cửa sổ nổi nhỏ, chuyển tab sang cửa sổ bên
  cạnh, trình chiếu slide hoặc PDF với iPhone làm remote và chấm laser.
- **Tải xuống** có bảng trên thanh tác vụ: tiến trình, tạm dừng, tải tiếp, huỷ. Kéo file từ Tệp thả vào trang web để
  tải lên.
- **Ghi màn hình** desktop (⌘ + Shift + 5) vào Ảnh và Tệp.
- **Tệp**: file tải về và ảnh chụp màn hình, thư mục, đổi tên, chuyển chỗ, tìm (theo tên và theo nội dung file), sắp
  xếp, tạo file chữ, nén và giải nén zip, thùng rác để khôi phục file, nhập từ iPhone, xem nhanh (Space). File chữ mở trong trình soạn tự lưu, có tìm và thay thế, Lưu thành.
- **App iOS từ file IPA đã giải mã**, chạy trong cửa sổ, nhiều app cùng lúc, tự mở lại ở lần sau. Nếu iDesk bị thoát
  bất thường thì app không tự mở lại, và trang App đánh dấu app đang dùng lúc đó.
- **iPhone làm thiết bị nhập**: cử chỉ trackpad, gõ mọi ngôn ngữ (Telex, VNI…), gõ bằng giọng nói, bàn phím Bluetooth
  (cả phím âm lượng và phát/dừng), chuột qua AssistiveTouch, tay cầm chơi game, emoji (⌃⌘Space), gõ tắt, và nút dán
  thứ bạn đã sao chép trên iPhone (ví dụ mật khẩu).
- **Desktop**: biểu tượng tự sắp và chỉnh cỡ, file trên desktop, hình nền (mỗi màn hình ảo một hình, hoặc hình đổi màu
  theo giờ), widget kéo thả tự do (đồng hồ, lịch tháng, thời tiết, sự kiện, lời nhắc, hẹn giờ tập trung), lọc ánh sáng
  xanh, lắc chuột để tìm con trỏ, khoá bằng Face ID và màn hình chờ, bảng nhanh và thông báo, pin, nhiệt độ và bộ nhớ
  trên khay, độ phân giải màn hình và viền TV.
- **Laptop làm màn hình**: không cần cáp. iDesk hiện desktop trong trình duyệt của laptop qua Wi-Fi, điều khiển bằng
  chuột và bàn phím của laptop (gõ tiếng Việt bằng bộ gõ của laptop được). Máy Mac còn nhận được desktop qua AirPlay.
- **Kiểm tra thiết lập** trên iPhone: màn hình, bàn phím, chuột, dung lượng trống, app, mỗi mục kèm cách sửa dễ hiểu.
  Trang Ứng dụng có danh sách app mọi người đã chạy được (compat.json, dài thêm theo báo cáo) và nút **Báo cáo** cho
  từng app.
- **Chế độ TV** một chạm (720p, chữ và biểu tượng to); tự tạm đóng tab không dùng khi sắp hết bộ nhớ; tự dọn file thừa
  khi cài hay cập nhật bị ngắt, và dọn được bộ nhớ đệm của app.
- Kiểm tra bản mới trên GitHub Releases: nút **Cập nhật** tải iDesk mới và gộp sẵn các app iOS của bạn vào, chỉ cần
  ký bằng ESign một lần là có bản mới mà vẫn giữ app.
- Hướng dẫn lần đầu, báo lỗi khi thoát hoặc treo kèm nút **Sao chép lỗi**, tiếng Anh và tiếng Việt.

## Cài đặt

Cần iPhone **iOS 17+** và cáp USB-C → HDMI/DisplayPort (hoặc bộ chuyển Lightning AV của Apple).

Tải `iDesk-<phiên bản>.ipa` ở [Releases](https://github.com/itshieuk/iDesk/releases), rồi ký và cài bằng ESign,
Feather hoặc Scarlet. Tự build (Xcode 15+ và [XcodeGen](https://github.com/yonaskolb/XcodeGen)):

```bash
brew install xcodegen
git clone https://github.com/itshieuk/iDesk.git && cd iDesk
xcodegen
scripts/build-ipa.sh      # → build/iDesk.ipa (hoặc mở iDesk.xcodeproj và bấm Run)
```

## Sử dụng

Mở iDesk, rồi cắm màn hình.

| Trên iPhone            | Làm gì                      | Bàn phím (⌘ hoặc Ctrl) | Làm gì                        |
| ---------------------- | --------------------------- | ---------------------- | ----------------------------- |
| Một ngón               | Di chuyển con trỏ           | T / N / W              | Tab mới / cửa sổ mới, đóng    |
| Chạm / chạm hai ngón   | Bấm / chuột phải            | Shift + T              | Mở lại thứ vừa đóng           |
| Kéo hai ngón           | Cuộn                        | L / R                  | Thanh địa chỉ / tải lại       |
| Giữ rồi kéo            | Kéo hoặc đổi cỡ cửa sổ      | F / G                  | Tìm / chỗ tiếp theo           |
| Ba ngón ↑ / ↓ / chạm   | App gần đây / Desktop / Quay lại | = / − / 0         | Phóng to, thu nhỏ             |
| Chạm bốn ngón          | Menu ứng dụng               | Chỉ ⌘ / Tab            | Menu ứng dụng, App gần đây    |
| Xoay ngang iPhone      | Cả màn hình thành trackpad  | /                      | Mọi phím tắt                  |

Bàn phím không có ⌘ thì phím logo làm việc tương tự. Chuột chạy qua *Cài đặt → Trợ năng → Cảm ứng → AssistiveTouch*: khi đó iPhone hiện
bản sao desktop để trỏ vào (**Kiểm tra chuột** cho biết iDesk nhận được gì). Cài đặt nằm trên desktop; khi chưa cắm
màn hình, nút bánh răng trên iPhone chỉ còn phần trackpad và chuột.

## App iOS từ file IPA

1. Bấm **App** (nút hình hộp) trên iPhone và thêm file `.ipa` đã giải mã.
2. Bấm **Cài app mới vào iDesk** rồi chọn ESign: ESign ký lại iDesk kèm các app bên trong và cài đặt.
3. Mở lại iDesk: các app nằm trong menu ứng dụng.

iOS chỉ chạy code nằm trong một app đã cài, nên phải cài lại (với chứng chỉ phát triển, mục **Nâng cao** ký app ngay
trên iPhone). App cài từ App Store không hiện được: iOS giữ mỗi app trong hộp cát riêng.

Phần lớn app chạy được: màn hình, chạm, gõ, mạng, đăng nhập, dữ liệu đã lưu. Không có: thông báo đẩy, iCloud, chạy
nền và tiện ích mở rộng. App kiểm tra bị sửa đổi có thể tự thoát, và mọi app dùng chung bộ nhớ của iDesk. Nếu một app
làm iDesk thoát, lần mở sau sẽ hiện **Sao chép lỗi**: hãy gửi nội dung đó.

## Phát triển

- `-iDeskPreview` hiện desktop trên màn hình iPhone (chạm trực tiếp; giữ để chuột phải). Thêm `-iDeskInstall <ipa…>`
  hoặc `-iDeskOpen <url>`. `scripts/sim-ipa.sh App.ipa` chuyển IPA để chạy trên Simulator.
- Code: `App/` các scene, `Desktop/` desktop và trình duyệt, `Controller/` màn hình iPhone, `Input/` chuột, `Guest/`
  nạp app (sửa Mach-O, vòng đời, shim cho bundle, keychain và hook dùng chung, chạm giả, báo lỗi).
- Chuỗi chữ: `iDesk/Localizable.xcstrings`. Phát hành: đẩy tag như `v0.5.2`.

**Lỗi đã biết:** trang web nhận sự kiện chuột qua JavaScript nên CSS `:hover` không có tác dụng và vài trang canvas
bỏ qua cú bấm. Khi chưa cắm màn hình, chỉ quản lý app được.

[MIT](LICENSE) · Chỉ nạp app bạn có quyền dùng. iDesk không liên quan tới Apple hay nhà phát triển app nào.
