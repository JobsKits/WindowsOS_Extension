// RunnerHost.cs | JobsFlutterRunner
// Created by Jobs on 2026年10月20日，星期二.
// CMD 只连接日志与控制文件；独立后台监督进程持有 Flutter 管道和专属 Job。
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;

namespace JobsFlutterRunner {
    public static class Program {
        private static readonly JavaScriptSerializer Json = new JavaScriptSerializer();
        private static readonly object LogLock = new object();
        private static string session;
        private static string appId;
        private static int sequence;
        private static Dictionary<string, object> state;
        private static readonly UTF8Encoding Utf8 = new UTF8Encoding(false);

        public static string Quote(string value) {
            StringBuilder output = new StringBuilder("\"");
            int slashes = 0;
            foreach (char item in value) {
                if (item == '\\') { slashes++; continue; }
                output.Append('\\', item == '"' ? slashes * 2 + 1 : slashes);
                output.Append(item);
                slashes = 0;
            }
            output.Append('\\', slashes * 2);
            return output.Append('"').ToString();
        }
        private static void SaveState() {
            lock (LogLock) {
                string temporary = Path.Combine(session, "state-" + Guid.NewGuid().ToString("N") + ".tmp");
                File.WriteAllText(temporary, Json.Serialize(state), Utf8);
                string target = Path.Combine(session, "state.json");
                if (File.Exists(target)) File.Replace(temporary, target, null);
                else File.Move(temporary, target);
            }
        }
        private static void Log(string text) {
            lock (LogLock) File.AppendAllText(Path.Combine(session, "run.log"), text + Environment.NewLine, Utf8);
        }
        private static object Value(Dictionary<string, object> item, string key) {
            object output;
            return item.TryGetValue(key, out output) ? output : null;
        }
        private static void Receive(string line, bool error) {
            if (line == null) return;
            lock (LogLock) {
                File.AppendAllText(Path.Combine(session, "machine.jsonl"), line + Environment.NewLine, Utf8);
                if (!error && line.StartsWith("[", StringComparison.Ordinal)) {
                    try {
                        object[] messages = Json.DeserializeObject(line) as object[];
                        if (messages != null) foreach (object entry in messages) {
                            var message = entry as Dictionary<string, object>;
                            if (message == null) continue;
                            var parameters = Value(message, "params") as Dictionary<string, object>;
                            string eventName = Convert.ToString(Value(message, "event"));
                            if (parameters != null && eventName == "app.start") {
                                appId = Convert.ToString(Value(parameters, "appId"));
                                state["AppId"] = appId;
                                SaveState();
                            }
                            if (parameters != null && eventName == "app.started") {
                                state["Status"] = "Running";
                                SaveState();
                                Log("Flutter 已启动；r 热重载，R 热重启，s 停止，q 关闭日志窗口。关闭 CMD 后继续运行。");
                            }
                            if (parameters != null) {
                                object text = Value(parameters, "log") ?? Value(parameters, "message");
                                if (text != null) Log(Convert.ToString(text));
                            }
                            object failure = Value(message, "error");
                            if (failure != null) Log("Flutter: " + Json.Serialize(failure));
                        }
                        return;
                    } catch (ArgumentException) { }
                }
                Log(line);
            }
        }
        private static void Send(Process flutter, string command) {
            lock (LogLock) {
                if (String.IsNullOrEmpty(appId)) { Log("Flutter 尚未返回 appId，请等待编译 / 安装完成后再操作。"); return; }
                var parameters = new Dictionary<string, object> { { "appId", appId } };
                string method = "app.stop";
                if (command != "stop") {
                    method = "app.restart";
                    parameters["fullRestart"] = command == "restart";
                    parameters["pause"] = false;
                    parameters["reason"] = "Jobs CMD";
                }
                var message = new Dictionary<string, object> { { "id", ++sequence }, { "method", method }, { "params", parameters } };
                flutter.StandardInput.WriteLine(Json.Serialize(new object[] { message }));
                flutter.StandardInput.Flush();
            }
        }
        private static int Worker(string requestFile) {
            var request = Json.Deserialize<Dictionary<string, string>>(File.ReadAllText(requestFile, Encoding.UTF8));
            session = Path.GetDirectoryName(Path.GetFullPath(requestFile));
            string project = request["Project"];
            string flutterPath = request["Flutter"];
            string device = request["Device"];
            if (!Directory.Exists(project) || !File.Exists(flutterPath) || String.IsNullOrWhiteSpace(device) ||
                device.IndexOfAny(new char[] { '"', '\r', '\n', '\0' }) >= 0) throw new InvalidOperationException("无效的项目、Flutter 或设备。");
            // 文件锁在后台进程持有；终端退出不影响锁，重复右键只能重连。
            string lockPath = Path.Combine(Path.GetDirectoryName(session), "active.lock");
            using (var ownership = new FileStream(lockPath, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None))
            using (Process owner = Process.GetCurrentProcess()) {
                state = new Dictionary<string, object> {
                    { "Project", project }, { "Flutter", flutterPath }, { "Device", device },
                    { "WorkerPid", owner.Id }, { "WorkerStartUtc", owner.StartTime.ToUniversalTime().ToString("o") },
                    { "Status", "Starting" }, { "Session", session }, { "StartedUtc", DateTime.UtcNow.ToString("o") }
                };
                SaveState();
                Log("项目：" + project + Environment.NewLine + "Flutter：" + flutterPath + Environment.NewLine + "设备：" + device);
                using (var child = new Process()) {
                    child.StartInfo.UseShellExecute = false;
                    child.StartInfo.CreateNoWindow = true;
                    child.StartInfo.WorkingDirectory = project;
                    child.StartInfo.RedirectStandardInput = true;
                    child.StartInfo.RedirectStandardOutput = true;
                    child.StartInfo.RedirectStandardError = true;
                    child.StartInfo.StandardOutputEncoding = Utf8;
                    child.StartInfo.StandardErrorEncoding = Utf8;
                    child.StartInfo.EnvironmentVariables["FLUTTER_SUPPRESS_ANALYTICS"] = "true";
                    child.StartInfo.EnvironmentVariables["DART_SUPPRESS_ANALYTICS"] = "true";
                    string gate = Path.Combine(session, "launch.cmd");
                    File.WriteAllText(gate, "@echo off\r\nset /p \"JOBS_FLUTTER_RUNNER_GATE=\"\r\nif not \"%JOBS_FLUTTER_RUNNER_GATE%\"==\"START\" exit /b 2\r\n\"%JOBS_FLUTTER_RUNNER_EXECUTABLE%\" run --machine -d \"%JOBS_FLUTTER_RUNNER_DEVICE%\"\r\n", Encoding.ASCII);
                    child.StartInfo.FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "cmd.exe");
                    child.StartInfo.EnvironmentVariables["JOBS_FLUTTER_RUNNER_EXECUTABLE"] = flutterPath;
                    child.StartInfo.EnvironmentVariables["JOBS_FLUTTER_RUNNER_DEVICE"] = device;
                    child.StartInfo.EnvironmentVariables["JOBS_FLUTTER_RUNNER_GATE_SCRIPT"] = gate;
                    child.StartInfo.EnvironmentVariables.Remove("JOBS_FLUTTER_RUNNER_GATE");
                    child.StartInfo.Arguments = "/d /v:off /s /c \"\"%JOBS_FLUTTER_RUNNER_GATE_SCRIPT%\"\"";
                    child.OutputDataReceived += delegate(object sender, DataReceivedEventArgs args) { Receive(args.Data, false); };
                    child.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs args) { Receive(args.Data, true); };
                    IntPtr job = Native.CreateKillJob();
                    try {
                        if (!child.Start()) throw new InvalidOperationException("Flutter 未启动。");
                        if (!Native.AssignProcessToJobObject(job, child.Handle)) {
                            child.Kill();
                            throw new InvalidOperationException("无法建立专属 Flutter 进程树，已停止本次启动。");
                        }
                        // CMD 先停在 stdin 门闩；归入 Job 后才释放，避免 Flutter 子进程抢跑。
                        child.StandardInput.WriteLine("START");
                        child.StandardInput.Flush();
                        state["FlutterPid"] = child.Id;
                        SaveState();
                        child.BeginOutputReadLine();
                        child.BeginErrorReadLine();
                        DateTime? stopAt = null;
                        while (!child.WaitForExit(150)) {
                            foreach (string path in Directory.GetFiles(session, "control-*.json")) {
                                try {
                                    Dictionary<string, string> control;
                                    lock (LogLock) control = Json.Deserialize<Dictionary<string, string>>(File.ReadAllText(path, Encoding.UTF8));
                                    string command = control["Command"];
                                    if (command == "stop") { stopAt = DateTime.UtcNow; Send(child, "stop"); }
                                    else if (command == "reload" || command == "restart") Send(child, command);
                                } catch (Exception failure) { Log("控制请求失败：" + failure.Message); }
                                finally { File.Delete(path); }
                            }
                            if (stopAt.HasValue && (DateTime.UtcNow - stopAt.Value).TotalSeconds >= 10) {
                                Log("停止等待超时，关闭本次 Flutter 的专属进程树。");
                                Native.TerminateJobObject(job, 1);
                                break;
                            }
                        }
                        child.WaitForExit();
                        state["Status"] = child.ExitCode == 0 || stopAt.HasValue ? "Stopped" : "Failed";
                        state["ExitCode"] = child.ExitCode;
                        Log("Flutter 已退出，退出码：" + child.ExitCode);
                    } catch (Exception failure) {
                        state["Status"] = "Failed";
                        Log("启动失败：" + failure.Message);
                    } finally {
                        Native.CloseHandle(job);
                        state["EndedUtc"] = DateTime.UtcNow.ToString("o");
                        SaveState();
                    }
                }
            }
            return 0;
        }
        [STAThread]
        public static int Main(string[] args) {
            try {
                if (args.Length != 2) return 2;
                if (args[0] == "start") {
                    string executable = typeof(Program).Assembly.Location;
                    Native.StartDetached(executable, Quote(executable) + " worker " + Quote(Path.GetFullPath(args[1])));
                    return 0;
                }
                if (args[0] == "worker") return Worker(args[1]);
                return 2;
            } catch (Exception failure) {
                if (args.Length == 2) {
                    try { File.WriteAllText(Path.Combine(Path.GetDirectoryName(Path.GetFullPath(args[1])), "startup-error.log"), failure.ToString(), Utf8); } catch { }
                }
                return 1;
            }
        }
    }
    internal static class Native {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct StartupInfo {
            public int cb; public string reserved; public string desktop; public string title;
            public int x, y, width, height, xChars, yChars, fill, flags;
            public short show, reservedSize; public IntPtr reserved2, stdin, stdout, stderr;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct ProcessInformation { public IntPtr process, thread; public int pid, threadId; }
        [StructLayout(LayoutKind.Sequential)]
        private struct BasicLimit {
            public long processTime, jobTime; public uint flags; public UIntPtr minWorking, maxWorking;
            public uint activeProcess; public UIntPtr affinity; public uint priority, scheduling;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct IoCounters { public ulong read, write, other, readBytes, writeBytes, otherBytes; }
        [StructLayout(LayoutKind.Sequential)]
        private struct ExtendedLimit { public BasicLimit basic; public IoCounters io; public UIntPtr processMemory, jobMemory, peakProcess, peakJob; }
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CreateProcess(string application, StringBuilder command, IntPtr processAttributes,
            IntPtr threadAttributes, bool inherit, uint flags, IntPtr environment, string directory, ref StartupInfo startup, out ProcessInformation result);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateJobObject(IntPtr attributes, string name);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool SetInformationJobObject(IntPtr job, int type, ref ExtendedLimit info, uint size);
        [DllImport("kernel32.dll", SetLastError = true)]
        internal static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
        [DllImport("kernel32.dll", SetLastError = true)]
        internal static extern bool TerminateJobObject(IntPtr job, uint code);
        [DllImport("kernel32.dll")]
        internal static extern bool CloseHandle(IntPtr handle);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool IsProcessInJob(IntPtr process, IntPtr job, out bool belongs);
        internal static IntPtr CreateKillJob() {
            IntPtr job = CreateJobObject(IntPtr.Zero, null);
            if (job == IntPtr.Zero) throw new System.ComponentModel.Win32Exception();
            ExtendedLimit limit = new ExtendedLimit();
            limit.basic.flags = 0x2000; // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE：只管理本次 Flutter 树。
            if (!SetInformationJobObject(job, 9, ref limit, (uint)Marshal.SizeOf(limit))) {
                CloseHandle(job);
                throw new System.ComponentModel.Win32Exception();
            }
            return job;
        }
        internal static void StartDetached(string executable, string command) {
            StartupInfo startup = new StartupInfo();
            startup.cb = Marshal.SizeOf(startup);
            ProcessInformation result;
            bool inJob;
            if (!IsProcessInJob(new IntPtr(-1), IntPtr.Zero, out inJob)) throw new System.ComponentModel.Win32Exception();
            uint flags = 0x00000008 | 0x00000200;
            if (inJob) flags |= 0x01000000;
            // 父 Job 不允许脱离时明确失败；不能把“无控制台”误报成“已脱离 Job”。
            if (!CreateProcess(executable, new StringBuilder(command), IntPtr.Zero, IntPtr.Zero, false,
                flags, IntPtr.Zero, Path.GetDirectoryName(executable), ref startup, out result))
                throw new InvalidOperationException(inJob ? "终端所属 Job 禁止独立后台运行；请从 Explorer 重新右键启动，或调整终端策略。" : "无法启动独立后台进程。", new System.ComponentModel.Win32Exception());
            CloseHandle(result.thread);
            CloseHandle(result.process);
        }
    }
}
