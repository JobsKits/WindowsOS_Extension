// HarmonyInstanceIdentity.cs | JobsHarmonySimulatorRepairer
// Created by Jobs on 2026年10月24日，星期六.
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace Jobs {
    public static class HarmonyInstanceIdentity {
        [StructLayout(LayoutKind.Sequential)]
        private struct Information {
            public uint Attributes, CreationLow, CreationHigh, AccessLow, AccessHigh, WriteLow, WriteHigh;
            public uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
        }
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle CreateFile(string path, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetFileInformationByHandle(SafeFileHandle file, out Information info);
        public static string Read(string path, bool directory) {
            using (SafeFileHandle file = CreateFile(path, 0x80, 7, IntPtr.Zero, 3, 0x02200000, IntPtr.Zero)) {
                if (file.IsInvalid) throw new Win32Exception();
                Information info;
                if (!GetFileInformationByHandle(file, out info)) throw new Win32Exception();
                if ((info.Attributes & 0x400) != 0 || ((info.Attributes & 0x10) != 0) != directory || (!directory && info.Links != 1)) throw new InvalidOperationException("Instance path is not an ordinary directory/configuration file");
                return info.Volume.ToString("X8") + "-" + info.IndexHigh.ToString("X8") + info.IndexLow.ToString("X8");
            }
        }
    }
}
