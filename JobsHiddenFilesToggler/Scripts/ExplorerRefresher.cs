// ExplorerRefresher.cs | JobsHiddenFilesToggler
// Created by Jobs on 2026年10月26日，星期一.
using System;
using System.Runtime.InteropServices;
namespace Jobs {
    public static class ExplorerRefresher {
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr SendMessageTimeout(IntPtr window, uint message, UIntPtr parameter, string area, uint flags, uint timeout, out UIntPtr result);
        [DllImport("shell32.dll")]
        private static extern void SHChangeNotify(uint eventId, uint flags, IntPtr item1, IntPtr item2);
        public static void Notify() {
            UIntPtr result;
            SendMessageTimeout(new IntPtr(0xffff), 0x001a, UIntPtr.Zero, "ShellState", 2, 1000, out result);
            IntPtr desktop = Marshal.AllocCoTaskMem(2);
            try {
                Marshal.WriteInt16(desktop, 0);
                SHChangeNotify(0x00001000, 0x00002000, desktop, IntPtr.Zero);
            } finally { Marshal.FreeCoTaskMem(desktop); }
        }
    }
}
