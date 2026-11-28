package org.magral.microgen.update;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.net.URL;
import java.net.URLConnection;
import java.net.URLStreamHandler;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.security.cert.Certificate;
import java.util.ArrayDeque;
import java.util.Arrays;
import javax.net.ssl.HttpsURLConnection;

public final class UpdaterDownloadTest {
    private static final String RELEASE =
            "https://github.com/Magral/Microgen/releases/download/defold-1.5.16/Microgen-Defold-1.5.16.apk";
    private static final byte[] APK = {1, 2, 3, 4, 5};
    private static final ArrayDeque<Reply> replies = new ArrayDeque<>();

    private record Reply(int code, byte[] body, String location) {}

    public static void main(String[] args) throws Exception {
        URL.setURLStreamHandlerFactory(protocol -> new URLStreamHandler() {
            @Override
            protected URLConnection openConnection(URL url) {
                return new HttpsURLConnection(url) {
                    private final Reply reply = replies.removeFirst();

                    @Override public int getResponseCode() { return reply.code(); }
                    @Override public String getHeaderField(String name) {
                        return "Location".equals(name) ? reply.location() : null;
                    }
                    @Override public ByteArrayInputStream getInputStream() {
                        return new ByteArrayInputStream(reply.body());
                    }
                    @Override public void disconnect() {}
                    @Override public boolean usingProxy() { return false; }
                    @Override public void connect() {}
                    @Override public String getCipherSuite() { return ""; }
                    @Override public Certificate[] getLocalCertificates() { return null; }
                    @Override public Certificate[] getServerCertificates() { return null; }
                };
            }
        });

        Path file = Files.createTempFile("microgen-update-test", ".apk");
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] expected = digest.digest(APK);
            replies.add(new Reply(302, null, "https://release-assets.githubusercontent.com/first.apk"));
            replies.add(new Reply(200, new byte[] {1, 2}, null));
            replies.add(new Reply(503, null, null));
            replies.add(new Reply(302, null, "https://release-assets.githubusercontent.com/fresh.apk"));
            replies.add(new Reply(200, APK, null));
            Updater.fetch(RELEASE, file.toFile(), APK.length, digest);
            if (!replies.isEmpty() || !Arrays.equals(Files.readAllBytes(file), APK)
                    || !MessageDigest.isEqual(expected, digest.digest())) {
                throw new AssertionError("Retry must replace the partial file and reset SHA-256");
            }

            replies.add(new Reply(200, new byte[] {1, 2, 3, 4, 5, 6}, null));
            expectFailure(file, digest, "APK exceeds expected size");
            replies.add(new Reply(302, null, "https://example.invalid/update.apk"));
            expectFailure(file, digest, "Untrusted release URL");
            for (int i = 0; i < 3; i++) replies.add(new Reply(200, new byte[] {1}, null));
            expectFailure(file, digest, "Incomplete APK");
            if (!replies.isEmpty()) throw new AssertionError("Unused HTTP responses");
            System.out.println("MICROGEN ANDROID UPDATE RETRY READY");
        } finally {
            Files.deleteIfExists(file);
        }
    }

    private static void expectFailure(Path file, MessageDigest digest, String message) throws IOException {
        try {
            Updater.fetch(RELEASE, file.toFile(), APK.length, digest);
            throw new AssertionError("Expected failure: " + message);
        } catch (IOException failure) {
            if (!message.equals(failure.getMessage())) throw failure;
            if (Files.exists(file)) throw new AssertionError("Unverified file was left on disk");
        }
    }
}
