# Triển khai upload ảnh

Đã kiểm tra project `uijplnwxyrhlgmenzyls`: endpoint `upload-image` hiện trả `404 NOT_FOUND`; ảnh `wolf.png` trong bucket `ha_giang` tải được thành công. Publishable key hiện tại đã được cập nhật trong `ha_giang.html`. Function lấy khóa public từ header `apikey` gửi từ trang, kiểm tra mật khẩu chỉnh sửa rồi mới dùng khóa service role ở phía server để thao tác Storage.

Trong PowerShell tại thư mục dự án, đăng nhập Supabase CLI rồi deploy:

```powershell
npx supabase@latest login
npx supabase@latest functions deploy upload-image --project-ref uijplnwxyrhlgmenzyls
```

Mã function nằm ở [functions/upload-image/index.ts](functions/upload-image/index.ts). Function xử lý CORS `OPTIONS`, xác thực mật khẩu chỉnh sửa, rồi tải/liệt kê/xóa ảnh trong bucket `ha_giang`. Nếu bucket chưa tồn tại, function tạo bucket public giới hạn 5 MB, chỉ nhận JPG, PNG và WebP. Function tắt gateway JWT verification vì nó kiểm tra mật khẩu chỉnh sửa bên trong; service role key chỉ được dùng bên trong Edge Function, không đặt trong `ha_giang.html`.

Không đặt Secret/service_role key trong `ha_giang.html`. Function vẫn cần khóa service role do Supabase cấp trong môi trường Edge Function để tạo/quản lý bucket và ghi/xóa file.
