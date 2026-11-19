#include <dmsdk/sdk.h>

#if defined(DM_PLATFORM_ANDROID)
#include <dmsdk/dlib/android.h>
#include <dmsdk/graphics/graphics_native.h>

static const char* JAVA_CLASS = "org.magral.microgen.update.Updater";

static int Download(lua_State* L)
{
    const char* path = luaL_checkstring(L, 1);
    const char* sha = luaL_checkstring(L, 2);
    jint size = (jint)luaL_checkinteger(L, 3);
    dmAndroid::ThreadAttacher thread;
    JNIEnv* env = thread.GetEnv();
    jobject activity = dmGraphics::GetNativeAndroidActivity();
    jclass cls = dmAndroid::LoadClass(env, activity, JAVA_CLASS);
    if (cls) {
        jmethodID method = env->GetStaticMethodID(cls, "download", "(Landroid/app/Activity;Ljava/lang/String;Ljava/lang/String;I)V");
        if (method) {
            jstring file = env->NewStringUTF(path);
            jstring digest = env->NewStringUTF(sha);
            env->CallStaticVoidMethod(cls, method, activity, file, digest, size);
            env->DeleteLocalRef(digest);
            env->DeleteLocalRef(file);
        }
        env->DeleteLocalRef(cls);
    }
    const bool ok = cls && !env->ExceptionCheck();
    if (env->ExceptionCheck()) env->ExceptionClear();
    lua_pushboolean(L, ok);
    return 1;
}

static int Invoke(lua_State* L, const char* name)
{
    dmAndroid::ThreadAttacher thread;
    JNIEnv* env = thread.GetEnv();
    jobject activity = dmGraphics::GetNativeAndroidActivity();
    jclass cls = dmAndroid::LoadClass(env, activity, JAVA_CLASS);
    jint status = -1;
    if (cls) {
        jmethodID method = env->GetStaticMethodID(cls, name, "(Landroid/app/Activity;)I");
        if (method) status = env->CallStaticIntMethod(cls, method, activity);
        env->DeleteLocalRef(cls);
    }
    if (env->ExceptionCheck()) {
        env->ExceptionClear();
        status = -1;
    }
    lua_pushinteger(L, status);
    return 1;
}

static int Status(lua_State* L) { return Invoke(L, "status"); }
static int Install(lua_State* L) { return Invoke(L, "install"); }
static int Allow(lua_State* L) { return Invoke(L, "allow"); }
#endif

static dmExtension::Result Initialize(dmExtension::Params* params)
{
#if defined(DM_PLATFORM_ANDROID)
    const luaL_reg methods[] = {
        {"download", Download}, {"status", Status}, {"install", Install}, {"allow", Allow}, {0, 0}
    };
    luaL_register(params->m_L, "microgen_updater", methods);
    lua_pop(params->m_L, 1);
#endif
    return dmExtension::RESULT_OK;
}

DM_DECLARE_EXTENSION(MicrogenUpdater, "MicrogenUpdater", 0, 0, Initialize, 0, 0, 0)
