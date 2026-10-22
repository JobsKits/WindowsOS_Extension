// GitShim.cs | JobsGitProxyConfigurator
// Created by Jobs on 2026年10月22日，星期四.
using System;
using System.IO;
using System.Text;
using System.Diagnostics;
using System.Collections.Generic;
using System.Reflection;
namespace JobsGitProxy {
    public sealed class Result {
        public int ExitCode;
        public string Output;
        public string Error;
    }
    public static class Bridge {
        // Quote individual argv values without passing through cmd.exe.
        public static string Quote(string value) {
            StringBuilder result = new StringBuilder("\"");
            int slashes = 0;
            foreach (char c in value) {
                if (c == '\\') { slashes++; continue; }
                if (c == '"') { result.Append('\\', slashes * 2 + 1); result.Append('"'); slashes = 0; continue; }
                result.Append('\\', slashes); slashes = 0; result.Append(c);
            }
            result.Append('\\', slashes * 2); result.Append('"');
            return result.ToString();
        }
        public static string Join(string[] arguments) {
            List<string> result = new List<string>();
            foreach (string item in arguments) result.Add(Quote(item));
            return String.Join(" ", result.ToArray());
        }
        public static string Encode(string[] arguments) {
            return Convert.ToBase64String(Encoding.UTF8.GetBytes(String.Join("\0", arguments)));
        }
        public static string[] Decode(string value) {
            return Encoding.UTF8.GetString(Convert.FromBase64String(value)).Split(new char[] { '\0' }, StringSplitOptions.None);
        }
        public static bool IsNetwork(string[] arguments) {
            for (int i = 0; i < arguments.Length; i++) {
                string item = arguments[i];
                if (item == "-c" || item == "-C" || item == "--git-dir" || item == "--work-tree" ||
                    item == "--namespace" || item == "--config-env" || item == "--super-prefix") { i++; continue; }
                if (item.StartsWith("-")) continue;
                return item == "clone" || item == "fetch" || item == "pull" || item == "ls-remote" || item == "push";
            }
            return false;
        }
        private static ProcessStartInfo StartInfo(string executable, string[] arguments, string directory) {
            ProcessStartInfo info = new ProcessStartInfo(executable, Join(arguments));
            info.UseShellExecute = false;
            if (!String.IsNullOrEmpty(directory)) info.WorkingDirectory = directory;
            return info;
        }
        // Inherited OS handles preserve Git's stdin, stdout and stderr, including GUI pipes.
        public static int Execute(string executable, string[] arguments) {
            using (Process process = Process.Start(StartInfo(executable, arguments, null))) {
                process.WaitForExit(); return process.ExitCode;
            }
        }
        // Metadata stays in memory; no original Git diagnostic is written to audit.
        public static Result Capture(string executable, string[] arguments, string directory, int timeout) {
            ProcessStartInfo info = StartInfo(executable, arguments, directory);
            info.CreateNoWindow = true;
            info.RedirectStandardOutput = true;
            info.RedirectStandardError = true;
            info.StandardOutputEncoding = Encoding.UTF8;
            info.StandardErrorEncoding = Encoding.UTF8;
            using (Process process = Process.Start(info)) {
                var output = process.StandardOutput.ReadToEndAsync();
                var error = process.StandardError.ReadToEndAsync();
                if (!process.WaitForExit(timeout)) {
                    try { process.Kill(); } catch { }
                    process.WaitForExit();
                    return new Result { ExitCode = 28, Output = "", Error = "initial probe timeout" };
                }
                return new Result { ExitCode = process.ExitCode, Output = output.Result, Error = error.Result };
            }
        }
        public static int Main(string[] arguments) {
            try {
                string directory = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
                string original = File.ReadAllText(Path.Combine(directory, "real-git.path"), Encoding.UTF8).Trim();
                if (!File.Exists(original) || String.Equals(Path.GetFullPath(original),
                    Assembly.GetExecutingAssembly().Location, StringComparison.OrdinalIgnoreCase)) {
                    Console.Error.WriteLine("[Jobs Git] Original Git is unavailable; run configuration check."); return 128;
                }
                if (!IsNetwork(arguments)) return Execute(original, arguments);
                string shell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
                    @"WindowsPowerShell\v1.0\powershell.exe");
                string[] policyArguments = new string[] { "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
                    "-File", Path.Combine(directory, "Policy.ps1"), "-EncodedArguments", Encode(arguments) };
                if (Join(policyArguments).Length + shell.Length > 28000) {
                    Console.Error.WriteLine("[Jobs Git] Arguments are long; preserving native Git execution.");
                    return Execute(original, arguments);
                }
                return Execute(shell, policyArguments);
            } catch {
                Console.Error.WriteLine("[Jobs Git] Runtime entry failed; run configuration check."); return 128;
            }
        }
    }
}
