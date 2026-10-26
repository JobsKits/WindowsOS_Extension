// RunPermissionFile.cs | Jobs Windows file execution permissions
// Created by Jobs on 2026年10月24日，星期六.
// Keep one non-shared-write/delete handle for identity, content and DACL changes.
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using Microsoft.Win32.SafeHandles;
namespace Jobs {
    public sealed class RunPermissionFile : IDisposable {
        private SafeFileHandle handle;
        private const uint ReadControl = 0x20000, WriteDac = 0x40000, ReadAttributes = 0x80;
        [StructLayout(LayoutKind.Sequential)]
        private struct FileInfoNative {
            public uint Attributes, CreationLow, CreationHigh, AccessLow, AccessHigh, WriteLow, WriteHigh;
            public uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
        }
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle CreateFile(string path, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetFileInformationByHandle(SafeFileHandle file, out FileInfoNative info);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern uint GetFinalPathNameByHandle(SafeFileHandle file, StringBuilder path, uint size, uint flags);
        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern uint GetSecurityInfo(SafeFileHandle file, uint type, uint information, out IntPtr owner, out IntPtr group, out IntPtr dacl, out IntPtr sacl, out IntPtr descriptor);
        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern uint GetSecurityDescriptorLength(IntPtr descriptor);
        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool SetKernelObjectSecurity(SafeFileHandle file, uint information, byte[] descriptor);
        [DllImport("kernel32.dll")]
        private static extern IntPtr LocalFree(IntPtr pointer);
        public string Path { get; private set; }
        public string Identity { get; private set; }
        public string Hash { get; private set; }
        public static bool IsExecutablePath(string path) {
            string extension = System.IO.Path.GetExtension(path).ToLowerInvariant();
            string[] extensions = { ".exe", ".com", ".scr", ".cpl", ".bat", ".cmd", ".ps1", ".vbs", ".vbe", ".js", ".jse", ".wsf", ".wsh", ".hta", ".py", ".pyw", ".pl", ".rb", ".sh", ".bash", ".zsh", ".fish", ".ksh", ".csh", ".tcsh", ".php", ".lua", ".command" };
            return Array.IndexOf(extensions, extension) >= 0;
        }
        public RunPermissionFile(string path) {
            if (!IsExecutablePath(path)) throw new IOException("Only executable and script file formats support execution permissions");
            Path = System.IO.Path.GetFullPath(path);
            handle = CreateFile(Path, 0x80000000 | ReadControl | WriteDac | ReadAttributes, 1, IntPtr.Zero, 3, 0x00200000, IntPtr.Zero);
            if (handle.IsInvalid) { int error = Marshal.GetLastWin32Error(); handle.Dispose(); throw new Win32Exception(error, "Cannot open ordinary file with read/DACL rights"); }
            try {
                StringBuilder resolved = new StringBuilder(32768);
                uint length = GetFinalPathNameByHandle(handle, resolved, (uint)resolved.Capacity, 0);
                if (length == 0 || length >= resolved.Capacity) throw new Win32Exception();
                string finalPath = resolved.ToString();
                if (finalPath.StartsWith(@"\\?\", StringComparison.Ordinal)) finalPath = finalPath.Substring(4);
                if (!String.Equals(finalPath, Path, StringComparison.OrdinalIgnoreCase)) throw new IOException("Resolved path changed or passes through an alias");
                FileInfoNative info;
                if (!GetFileInformationByHandle(handle, out info)) throw new Win32Exception();
                if ((info.Attributes & (0x10u | 0x400u)) != 0 || info.Links != 1) throw new IOException("Directories, reparse points and hard-linked files are excluded");
                Identity = info.Volume.ToString("X8") + "-" + info.IndexHigh.ToString("X8") + info.IndexLow.ToString("X8");
                using (SafeFileHandle alias = new SafeFileHandle(handle.DangerousGetHandle(), false))
                using (FileStream stream = new FileStream(alias, FileAccess.Read))
                using (SHA256 digest = SHA256.Create()) { Hash = BitConverter.ToString(digest.ComputeHash(stream)).Replace("-", ""); }
            } catch { handle.Dispose(); throw; }
        }
        public string Capture() {
            IntPtr owner, group, dacl, sacl, descriptor;
            uint error = GetSecurityInfo(handle, 1, 4, out owner, out group, out dacl, out sacl, out descriptor);
            if (error != 0) throw new Win32Exception((int)error);
            try {
                byte[] bytes = new byte[GetSecurityDescriptorLength(descriptor)];
                Marshal.Copy(descriptor, bytes, 0, bytes.Length);
                return new RawSecurityDescriptor(bytes, 0).GetSddlForm(AccessControlSections.Access);
            } finally { LocalFree(descriptor); }
        }
        public static string Build(string original, string sid, bool allow) {
            RawSecurityDescriptor security = new RawSecurityDescriptor(original);
            if (security.DiscretionaryAcl == null) throw new IOException("NULL DACL is not managed automatically");
            RawAcl acl = security.DiscretionaryAcl;
            CommonAce entry = new CommonAce(AceFlags.None, allow ? AceQualifier.AccessAllowed : AceQualifier.AccessDenied, 32, new SecurityIdentifier(sid), false, null);
            int position = 0;
            if (allow) {
                position = acl.Count;
                for (int index = 0; index < acl.Count; index++) {
                    if ((acl[index].AceFlags & AceFlags.Inherited) != 0) { position = index; break; }
                }
            }
            acl.InsertAce(position, entry);
            return security.GetSddlForm(AccessControlSections.Access);
        }
        public void Apply(string expectedBefore, string replacement) {
            if (!String.Equals(Capture(), expectedBefore, StringComparison.Ordinal)) throw new IOException("DACL changed concurrently; preserved current rules");
            RawSecurityDescriptor descriptor = new RawSecurityDescriptor(replacement);
            byte[] bytes = new byte[descriptor.BinaryLength];
            descriptor.GetBinaryForm(bytes, 0);
            if (!SetKernelObjectSecurity(handle, 4, bytes)) throw new Win32Exception();
            if (!String.Equals(Capture(), replacement, StringComparison.Ordinal)) throw new IOException("DACL verification failed");
        }
        public bool HasExecute() {
            using (SafeFileHandle check = CreateFile(Path, 32, 1, IntPtr.Zero, 3, 0x00200000, IntPtr.Zero)) {
                if (!check.IsInvalid) {
                    FileInfoNative info;
                    if (!GetFileInformationByHandle(check, out info)) throw new Win32Exception();
                    string identity = info.Volume.ToString("X8") + "-" + info.IndexHigh.ToString("X8") + info.IndexLow.ToString("X8");
                    if (identity != Identity) throw new IOException("Target identity changed");
                    return true;
                }
                int error = Marshal.GetLastWin32Error();
                if (error == 5) return false;
                throw new Win32Exception(error, "Cannot verify ExecuteFile access");
            }
        }
        public void Dispose() { if (handle != null) handle.Dispose(); }
    }
}
