// FlutterRunnerMenuProbe.cs | WindowsOS@Extension 隔离原生 COM 探针
// Created by Jobs on 2026年10月20日，星期二.
// 直接调用本次 DLL 类工厂和临时 HMENU，不注册 COM、不打开实际右键菜单。
using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

namespace JobsFlutterRunnerTests {
    [ComImport, Guid("00000001-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IClassFactory {
        [PreserveSig] int CreateInstance(IntPtr outer, ref Guid iid, out IntPtr instance);
        [PreserveSig] int LockServer(bool value);
    }
    [ComImport, Guid("000214E8-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IShellExtInit {
        [PreserveSig] int Initialize(IntPtr directory, [MarshalAs(UnmanagedType.Interface)] IDataObject selection, IntPtr key);
    }
    [ComImport, Guid("000214E4-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IContextMenu {
        [PreserveSig] int QueryContextMenu(IntPtr menu, uint position, uint first, uint last, uint flags);
        [PreserveSig] int InvokeCommand(IntPtr information);
        [PreserveSig] int GetCommandString(UIntPtr command, uint flags, IntPtr reserved, IntPtr name, uint length);
    }
    public static class MenuProbe {
        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        delegate int GetClassObject(ref Guid clsid, ref Guid iid, out IntPtr result);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr LoadLibrary(string file);
        [DllImport("kernel32.dll", CharSet = CharSet.Ansi)] static extern IntPtr GetProcAddress(IntPtr module, string name);
        [DllImport("kernel32.dll")] static extern bool FreeLibrary(IntPtr module);
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)] static extern int SHParseDisplayName(string name, IntPtr bind, out IntPtr pidl, uint attributes, out uint result);
        [DllImport("shell32.dll")] static extern IntPtr ILCloneFull(IntPtr pidl);
        [DllImport("shell32.dll")] static extern bool ILRemoveLastID(IntPtr pidl);
        [DllImport("shell32.dll")] static extern IntPtr ILFindLastID(IntPtr pidl);
        [DllImport("shell32.dll")] static extern int SHCreateDataObject(IntPtr parent, uint count, IntPtr[] children, IDataObject inner, ref Guid iid, out IDataObject result);
        [DllImport("user32.dll")] static extern IntPtr CreatePopupMenu();
        [DllImport("user32.dll")] static extern bool DestroyMenu(IntPtr menu);
        [DllImport("user32.dll")] static extern int GetMenuItemCount(IntPtr menu);
        public static int Count(string library, string directory, int selections) {
            IntPtr module = LoadLibrary(library);
            if (module == IntPtr.Zero) throw new System.ComponentModel.Win32Exception();
            object factoryObject = null, menuObject = null;
            IntPtr pidl = IntPtr.Zero, parent = IntPtr.Zero, menu = IntPtr.Zero;
            IDataObject selection = null;
            try {
                Guid clsid = new Guid("239D7884-83C5-4D66-AB0C-14A2667DCD61");
                Guid factoryId = typeof(IClassFactory).GUID, initId = typeof(IShellExtInit).GUID;
                var getFactory = (GetClassObject)Marshal.GetDelegateForFunctionPointer(GetProcAddress(module, "DllGetClassObject"), typeof(GetClassObject));
                IntPtr pointer;
                Marshal.ThrowExceptionForHR(getFactory(ref clsid, ref factoryId, out pointer));
                factoryObject = Marshal.GetObjectForIUnknown(pointer);
                Marshal.Release(pointer);
                Marshal.ThrowExceptionForHR(((IClassFactory)factoryObject).CreateInstance(IntPtr.Zero, ref initId, out pointer));
                menuObject = Marshal.GetObjectForIUnknown(pointer);
                Marshal.Release(pointer);
                uint attributes;
                Marshal.ThrowExceptionForHR(SHParseDisplayName(directory, IntPtr.Zero, out pidl, 0, out attributes));
                IntPtr directoryPidl = pidl;
                if (selections > 0) {
                    parent = ILCloneFull(pidl);
                    if (parent == IntPtr.Zero || !ILRemoveLastID(parent)) throw new InvalidOperationException("Cannot obtain parent PIDL.");
                    IntPtr[] children = new IntPtr[selections];
                    for (int index = 0; index < selections; index++) children[index] = ILFindLastID(pidl);
                    Guid dataId = typeof(IDataObject).GUID;
                    Marshal.ThrowExceptionForHR(SHCreateDataObject(parent, (uint)children.Length, children, null, ref dataId, out selection));
                    directoryPidl = parent;
                }
                Marshal.ThrowExceptionForHR(((IShellExtInit)menuObject).Initialize(directoryPidl, selection, IntPtr.Zero));
                menu = CreatePopupMenu();
                if (menu == IntPtr.Zero) throw new System.ComponentModel.Win32Exception();
                Marshal.ThrowExceptionForHR(((IContextMenu)menuObject).QueryContextMenu(menu, 0, 1, 100, 0));
                return GetMenuItemCount(menu);
            } finally {
                if (menu != IntPtr.Zero) DestroyMenu(menu);
                if (selection != null) Marshal.FinalReleaseComObject(selection);
                if (menuObject != null) Marshal.FinalReleaseComObject(menuObject);
                if (factoryObject != null) Marshal.FinalReleaseComObject(factoryObject);
                if (parent != IntPtr.Zero) Marshal.FreeCoTaskMem(parent);
                if (pidl != IntPtr.Zero) Marshal.FreeCoTaskMem(pidl);
                FreeLibrary(module);
            }
        }
    }
}
