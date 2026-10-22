import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-supabase-api-version",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const bucketName = "ha_giang";
const maxFileSize = 5 * 1024 * 1024;
const extensions: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
};

function readKey(name: string): string {
  const value = Deno.env.get(name);
  if (!value) return "";
  try {
    const keys = JSON.parse(value);
    return typeof keys.default === "string" ? keys.default : "";
  } catch {
    return value;
  }
}

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const fallbackPublicKey = readKey("SUPABASE_PUBLISHABLE_KEYS") || Deno.env.get("SUPABASE_ANON_KEY") || "";
const serviceKey = readKey("SUPABASE_SECRET_KEYS") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
  });
}

function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

async function ensureBucket(admin: ReturnType<typeof createClient>) {
  const { data: bucket, error } = await admin.storage.getBucket(bucketName);
  if (error && error.statusCode !== "404" && !/bucket.*not found/i.test(error.message)) throw error;

  if (!bucket) {
    const { error: createError } = await admin.storage.createBucket(bucketName, {
      public: true,
      fileSizeLimit: "5MB",
      allowedMimeTypes: Object.keys(extensions),
    });
    if (createError && !/already exists/i.test(createError.message)) throw createError;
  } else if (!bucket.public) {
    const { error: updateError } = await admin.storage.updateBucket(bucketName, { public: true });
    if (updateError) throw updateError;
  }
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Chỉ hỗ trợ POST." }, 405);
  if (!supabaseUrl || !serviceKey) {
    return json({ error: "Edge Function thiếu khóa Supabase cần thiết." }, 500);
  }

  try {
    let action = "";
    let password = "";
    let path = "";
    let file: File | null = null;

    if ((request.headers.get("content-type") ?? "").includes("multipart/form-data")) {
      const form = await request.formData();
      action = String(form.get("action") ?? "");
      password = String(form.get("password") ?? "");
      const uploaded = form.get("file");
      if (uploaded instanceof File) file = uploaded;
    } else {
      const body = await request.json();
      action = String(body.action ?? "");
      password = String(body.password ?? "");
      path = String(body.path ?? "");
    }

    if (!password) return json({ error: "Cần mật khẩu chỉnh sửa để quản lý ảnh." }, 400);
    if (!["upload", "list", "delete"].includes(action)) return json({ error: "Thao tác ảnh không hợp lệ." }, 400);

    const requestPublicKey = request.headers.get("apikey") || fallbackPublicKey;
    if (!requestPublicKey) return json({ error: "Thiếu Publishable key của ứng dụng." }, 401);

    const authClient = createClient(supabaseUrl, requestPublicKey, {
      auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
    });
    const { data: passwordValid, error: passwordError } = await authClient.rpc("check_edit_password", {
      p_password: password,
    });
    if (passwordError) return json({ error: `Không xác minh được mật khẩu: ${passwordError.message}` }, 500);
    if (passwordValid !== true) return json({ error: "Mật khẩu không đúng." }, 401);

    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
    });
    await ensureBucket(admin);
    const storage = admin.storage.from(bucketName);

    if (action === "upload") {
      if (!file) return json({ error: "Chưa nhận được tệp ảnh." }, 400);
      const extension = extensions[file.type];
      if (!extension) return json({ error: "Chỉ nhận ảnh JPG, PNG hoặc WebP." }, 415);
      if (file.size <= 0 || file.size > maxFileSize) return json({ error: "Ảnh phải có dung lượng tối đa 5 MB." }, 413);

      const objectPath = `${crypto.randomUUID()}.${extension}`;
      const { error: uploadError } = await storage.upload(objectPath, new Uint8Array(await file.arrayBuffer()), {
        cacheControl: "3600",
        contentType: file.type,
        upsert: false,
      });
      if (uploadError) return json({ error: uploadError.message }, 500);
      return json({ path: objectPath, publicUrl: storage.getPublicUrl(objectPath).data.publicUrl });
    }

    if (action === "list") {
      const { data, error: listError } = await storage.list("", {
        limit: 100,
        sortBy: { column: "created_at", order: "desc" },
      });
      if (listError) return json({ error: listError.message }, 500);
      return json({ items: (data ?? []).filter((item) => item.name).map((item) => ({
        path: item.name,
        publicUrl: storage.getPublicUrl(item.name).data.publicUrl,
      })) });
    }

    if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,180}\.(jpg|jpeg|png|webp)$/i.test(path) || path.includes("..")) {
      return json({ error: "Đường dẫn ảnh không hợp lệ." }, 400);
    }
    const { error: deleteError } = await storage.remove([path]);
    if (deleteError) return json({ error: deleteError.message }, 500);
    return json({ path, deleted: true });
  } catch (error) {
    console.error("upload-image failed:", error);
    return json({ error: messageOf(error) || "Không xử lý được ảnh." }, 500);
  }
});
