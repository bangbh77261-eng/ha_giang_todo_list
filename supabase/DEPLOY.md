# Triển khai upload ảnh

Đã kiểm tra project `uijplnwxyrhlgmenzyls`: endpoint `upload-image` hiện trả `404 NOT_FOUND`; ảnh `wolf.png` trong bucket `ha_giang` tải được thành công. Publishable key hiện tại đã được cập nhật trong `ha_giang.html`. Function lấy khóa public từ header `apikey` gửi từ trang, kiểm tra mật khẩu chỉnh sửa rồi mới dùng khóa service role ở phía server để thao tác Storage.

Trong PowerShell tại thư mục dự án, đăng nhập Supabase CLI rồi deploy:

```powershell
npx supabase@latest login
npx supabase@latest functions deploy upload-image --project-ref uijplnwxyrhlgmenzyls
```

Mã function nằm ở [functions/upload-image/index.ts](functions/upload-image/index.ts). Function xử lý CORS `OPTIONS`, xác thực mật khẩu chỉnh sửa, rồi tải/liệt kê/xóa ảnh trong bucket `ha_giang`. Nếu bucket chưa tồn tại, function tạo bucket public giới hạn 5 MB, chỉ nhận JPG, PNG và WebP. Function tắt gateway JWT verification vì nó kiểm tra mật khẩu chỉnh sửa bên trong; service role key chỉ được dùng bên trong Edge Function, không đặt trong `ha_giang.html`.

Không đặt Secret/service_role key trong `ha_giang.html`. Function vẫn cần khóa service role do Supabase cấp trong môi trường Edge Function để tạo/quản lý bucket và ghi/xóa file.

## Thông tin liên hệ thành viên

Để bật lưu số điện thoại và địa điểm Google Maps, mở `supabase-participant-contacts-migration.sql` trong Supabase SQL Editor và chạy một lần. Migration thêm hai cột vào `trip_participants` và RPC `save_trip_participant_contact`, kiểm tra mật khẩu chỉnh sửa trước khi cập nhật. Số điện thoại và địa điểm được đọc từ danh sách thành viên công khai nên người mở trang cũng xem được các thông tin đã nhập.

## Vị trí trực tiếp

Chạy `supabase-live-location-migration.sql` sau `supabase-expenses-and-task-time-migration.sql`, vì migration đó tạo danh sách thành viên và `device_sessions`. Mở trang qua HTTPS. Mỗi thành viên đăng nhập trên thiết bị của mình, chọn đúng tên, rồi tự bấm **Chia sẻ vị trí của tôi** và cấp quyền GPS. Bản đồ tải lại vị trí mỗi 5 giây; khi trang đang hoạt động, thiết bị lấy lại GPS khoảng 20 giây một lần kể cả khi người đó đứng yên. Giữ trang mở trong lúc chia sẻ. Vị trí chỉ được trả về qua RPC đã kiểm tra phiên đăng nhập; bảng tọa độ không cấp quyền đọc trực tiếp. Khi dừng, đăng xuất hoặc đổi tên thành viên trên cùng thiết bị, vị trí bị xóa; nếu thiết bị mất kết nối, marker hết hạn sau 90 giây. Bản đồ trong trang dùng Leaflet với nền OpenStreetMap; bấm marker mở chỉ đường trên Google Maps. Migration thông tin liên hệ là độc lập, không cần chạy để dùng vị trí trực tiếp.
