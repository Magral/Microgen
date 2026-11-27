package org.magral.microgen.update;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.net.Uri;
import android.provider.Settings;
import android.util.Log;
import java.io.File;
import java.io.IOException;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.URL;
import javax.net.ssl.HttpsURLConnection;
import java.security.MessageDigest;
import java.util.Arrays;
import java.net.SocketTimeoutException;
import javax.net.ssl.SSLException;

public final class Updater {
    private static volatile int state;
    private static volatile File verified;
    static final String APK = "microgen-verified-update.apk";

    private static final class UpdateFailure extends IOException {
        final int code;
        UpdateFailure(int code, String message) { super(message); this.code = code; }
    }

    public static synchronized void download(Activity activity, String url, String sha, int size) {
        if (state == 1) return;
        state = 1;
        verified = null;
        new Thread(() -> {
            File source = new File(activity.getCacheDir(), "microgen-update-pending.apk");
            try {
                if (!sha.matches("[0-9a-f]{64}") || size <= 0 || size > 150 * 1024 * 1024) throw new IOException();
                MessageDigest digest = MessageDigest.getInstance("SHA-256");
                fetch(url, source, size, digest);
                StringBuilder hex = new StringBuilder(64);
                for (byte b : digest.digest()) {
                    hex.append(Character.forDigit((b >>> 4) & 15, 16));
                    hex.append(Character.forDigit(b & 15, 16));
                }
                if (!sha.contentEquals(hex)) throw new UpdateFailure(-3, "SHA-256 mismatch");
                PackageManager manager = activity.getPackageManager();
                String name = activity.getPackageName();
                PackageInfo old = manager.getPackageInfo(name, PackageManager.GET_SIGNATURES);
                PackageInfo next = manager.getPackageArchiveInfo(source.getAbsolutePath(), PackageManager.GET_SIGNATURES);
                if (next == null || !name.equals(next.packageName) || next.versionCode <= old.versionCode)
                    throw new UpdateFailure(-4, "APK package or version mismatch");
                if (!sameSignatures(old.signatures, next.signatures))
                    throw new UpdateFailure(-5, "APK signing certificate mismatch");
                File target = new File(activity.getCacheDir(), APK);
                if (!source.renameTo(target)) {
                    java.nio.file.Files.move(source.toPath(), target.toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING);
                }
                verified = target;
                state = 2;
            } catch (Exception failure) {
                source.delete();
                state = failure instanceof UpdateFailure ? ((UpdateFailure) failure).code
                    : failure instanceof SocketTimeoutException ? -7
                    : failure instanceof SSLException ? -8 : -1;
                Log.w("MicrogenUpdater", "Update failed, code " + state + ": "
                    + failure.getClass().getSimpleName() + ": " + failure.getMessage(), failure);
            }
        }, "microgen-verify-update").start();
    }

    private static void fetch(String address, File source, int size, MessageDigest digest) throws IOException {
        URL url = new URL(address);
        if (!"github.com".equals(url.getHost())
                || !url.getPath().startsWith("/Magral/Microgen/releases/download/defold-")) throw new IOException();
        IOException lastFailure = null;
        for (int retry = 0; retry < 3; retry++) {
            digest.reset();
            source.delete();
            try {
              for (int redirect = 0; redirect < 8; redirect++) {
                if (!"https".equals(url.getProtocol())) throw new IOException("HTTPS redirect required");
                String host = url.getHost();
            if (!"github.com".equals(host) && !"release-assets.githubusercontent.com".equals(host)
                    && !"objects.githubusercontent.com".equals(host)
                    && !"github-releases.githubusercontent.com".equals(host)) throw new IOException();
            HttpsURLConnection connection = (HttpsURLConnection) url.openConnection();
            connection.setInstanceFollowRedirects(false);
            connection.setRequestProperty("Accept-Encoding", "identity");
            connection.setRequestProperty("User-Agent", "Microgen-Android-Updater");
            connection.setConnectTimeout(15000);
            connection.setReadTimeout(30000);
            try {
                int code = connection.getResponseCode();
                if (code >= 300 && code < 400) {
                    String location = connection.getHeaderField("Location");
                    if (location == null) throw new IOException("Redirect without Location");
                    URL redirected = new URL(url, location);
                    String nextHost = redirected.getHost();
                    if (!"https".equals(redirected.getProtocol())
                        || !("github.com".equals(nextHost)
                            || "release-assets.githubusercontent.com".equals(nextHost)
                            || "objects.githubusercontent.com".equals(nextHost)
                            || "github-releases.githubusercontent.com".equals(nextHost)))
                        throw new IOException("Untrusted redirect host: " + nextHost);
                    url = redirected;
                    continue;
                }
                if (code != 200) throw new UpdateFailure(-6, "HTTP " + code + " from " + host);
                try (InputStream input = connection.getInputStream(); FileOutputStream output = new FileOutputStream(source)) {
                    byte[] buffer = new byte[65536];
                    int total = 0;
                    int count;
                    while ((count = input.read(buffer)) != -1) {
                        total += count;
                        if (total > size) throw new UpdateFailure(-2, "APK exceeds expected size");
                        output.write(buffer, 0, count);
                        digest.update(buffer, 0, count);
                    }
                    if (total != size) throw new UpdateFailure(-2, "APK size mismatch");
                }
                return;
              } finally {
                connection.disconnect();
              }
              throw new IOException("Too many redirects");
            } catch (UpdateFailure rejected) {
                throw rejected;
            } catch (IOException transientFailure) {
                lastFailure = transientFailure;
                source.delete();
                if (retry == 2) throw transientFailure;
                try { Thread.sleep(700L * (retry + 1)); }
                catch (InterruptedException interrupted) {
                    Thread.currentThread().interrupt();
                    throw new IOException("Download retry interrupted", interrupted);
                }
            }
        }
        throw lastFailure == null ? new IOException("Download failed") : lastFailure;
    }

    private static boolean sameSignatures(Signature[] a, Signature[] b) {
        if (a == null || b == null || a.length == 0 || a.length != b.length) return false;
        return Arrays.asList(a).containsAll(Arrays.asList(b));
    }

    public static int status(Activity activity) { return state; }

    public static int install(Activity activity) {
        if (verified == null || !verified.isFile()) return -1;
        if (!activity.getPackageManager().canRequestPackageInstalls()) return 3;
        Uri uri = Uri.parse("content://" + activity.getPackageName() + ".updates/" + APK);
        Intent intent = new Intent(Intent.ACTION_VIEW);
        intent.setDataAndType(uri, "application/vnd.android.package-archive");
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        activity.runOnUiThread(() -> {
            try { activity.startActivity(intent); }
            catch (RuntimeException unavailable) { state = -1; }
        });
        return 2;
    }

    public static int allow(Activity activity) {
        Intent intent = new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:" + activity.getPackageName()));
        activity.runOnUiThread(() -> {
            try { activity.startActivity(intent); }
            catch (RuntimeException unavailable) { state = -1; }
        });
        return 3;
    }
}
