#Requires AutoHotkey v2.0

class AppPaths {
    static AppName := "kuangzi-app"

    static Root() {
        return EnvGet("USERPROFILE") "\.kuangzi"
    }

    static AppRoot() {
        return this.Root() "\app"
    }

    static AppDir() {
        return this.AppRoot() "\" this.AppName
    }

    static DataRoot() {
        return this.Root() "\data\" this.AppName
    }

    static ConfigFile() {
        return this.DataRoot() "\config.json"
    }

    static WriteProbe() {
        return this.DataRoot() "\.write-probe"
    }

    static PluginsDir() {
        return this.DataRoot() "\plugins"
    }

    static PluginDir(id) {
        return this.PluginsDir() "\" id
    }

    static LogsDir() {
        return this.DataRoot() "\logs"
    }

    static PathDir() {
        return this.DataRoot() "\path"
    }

    static TasksDir() {
        return this.DataRoot() "\plugin-tasks"
    }

    static BinDir() {
        return this.Root() "\bin"
    }

    static InstallExe() {
        exe := this.AppDir() "\kuangzi.exe"
        return FileExist(exe) ? exe : ""
    }

}
