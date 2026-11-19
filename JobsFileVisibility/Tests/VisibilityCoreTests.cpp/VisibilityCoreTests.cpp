// VisibilityCoreTests.cpp | JobsFileVisibility
// Created by Jobs on 2026年11月18日，星期三.
// Portable Win32 boundary fixtures; no real file attributes or Explorer registration are changed.
#include <algorithm>
#include <cstdint>
#include <cwchar>
#include <iostream>
#include <map>
#include <stdexcept>
#include <string>
#include <vector>
using DWORD = uint32_t;
using HANDLE = void*;
constexpr HANDLE INVALID_HANDLE_VALUE = nullptr;
constexpr DWORD ERROR_SUCCESS=0, ERROR_NOT_SUPPORTED=50, ERROR_INVALID_NAME=123,
    ERROR_FILE_INVALID=1006, ERROR_WRITE_FAULT=29, ERROR_ACCESS_DENIED=5;
constexpr DWORD FILE_ATTRIBUTE_READONLY=1, FILE_ATTRIBUTE_HIDDEN=2, FILE_ATTRIBUTE_SYSTEM=4,
    FILE_ATTRIBUTE_DIRECTORY=16, FILE_ATTRIBUTE_ARCHIVE=32, FILE_ATTRIBUTE_DEVICE=64,
    FILE_ATTRIBUTE_NORMAL=128, FILE_ATTRIBUTE_REPARSE_POINT=1024, FILE_ATTRIBUTE_COMPRESSED=2048;
constexpr DWORD FILE_READ_ATTRIBUTES=128, FILE_WRITE_ATTRIBUTES=256, FILE_SHARE_READ=1,
    FILE_SHARE_WRITE=2, FILE_SHARE_DELETE=4, OPEN_EXISTING=3,
    FILE_FLAG_BACKUP_SEMANTICS=0x02000000, FILE_FLAG_OPEN_REPARSE_POINT=0x00200000,
    SHCNE_UPDATEITEM=0x2000, SHCNE_ATTRIBUTES=0x800, SHCNF_PATHW=5;
enum { FileBasicInfo };
struct Stamp { int64_t QuadPart=0; };
struct FILE_BASIC_INFO { Stamp CreationTime, LastAccessTime, LastWriteTime, ChangeTime; DWORD FileAttributes=0; };
struct BY_HANDLE_FILE_INFORMATION { DWORD dwFileAttributes=0, dwVolumeSerialNumber=1, nFileIndexHigh=0, nFileIndexLow=1; };
struct File { DWORD attributes=0, id=1; bool denied=false, writeFailure=false, replacedAfterWrite=false, readFailure=false; };
static std::map<std::wstring, File> files;
static DWORD lastError=ERROR_ACCESS_DENIED;
static size_t writes=0, notices=0, opened=0, closed=0;
static bool timestampsUntouched=true, noFollow=true;
static DWORD GetLastError() { return lastError; }
static int _wcsicmp(const wchar_t* a,const wchar_t* b) { return wcscasecmp(a,b); }
static DWORD CopyPath(const std::wstring& path,DWORD count,wchar_t* output) {
    if (!count) return static_cast<DWORD>(path.size()+1);
    if (path.size()>=count) return static_cast<DWORD>(path.size()+1);
    std::copy(path.begin(),path.end(),output); output[path.size()]=0;
    return static_cast<DWORD>(path.size());
}
static DWORD GetFullPathNameW(const wchar_t* value,DWORD count,wchar_t* output,void*) {
    std::wstring path(value);
    if (path==L"C:\\folder\\..") path=L"C:\\";
    return CopyPath(path,count,output);
}
static bool GetVolumePathNameW(const wchar_t* path,wchar_t* output,DWORD count) {
    const std::wstring value(path);
    const std::wstring root = value.find(L"\\\\server\\share") == 0 ? L"\\\\server\\share\\" : L"C:\\";
    return CopyPath(root,count,output)!=0;
}
static HANDLE CreateFileW(const wchar_t* path,DWORD access,DWORD,void*,DWORD,DWORD flags,void*) {
    noFollow = noFollow && (flags & FILE_FLAG_OPEN_REPARSE_POINT) != 0;
    auto found=files.find(path);
    if (found==files.end() || found->second.denied) return INVALID_HANDLE_VALUE;
    if ((access & FILE_WRITE_ATTRIBUTES) && found->second.writeFailure) return INVALID_HANDLE_VALUE;
    ++opened;
    return &found->second;
}
static bool CloseHandle(HANDLE) { ++closed; return true; }
static bool GetFileInformationByHandle(HANDLE handle,BY_HANDLE_FILE_INFORMATION* output) {
    File& file=*static_cast<File*>(handle);
    if (file.readFailure) return false;
    output->dwFileAttributes=file.attributes; output->nFileIndexLow=file.id;
    return true;
}
static bool SetFileInformationByHandle(HANDLE handle,int,FILE_BASIC_INFO* info,size_t) {
    File& file=*static_cast<File*>(handle); ++writes;
    timestampsUntouched = timestampsUntouched && info->CreationTime.QuadPart==0 && info->LastAccessTime.QuadPart==0 && info->LastWriteTime.QuadPart==0 && info->ChangeTime.QuadPart==0;
    file.attributes=info->FileAttributes;
    if (file.replacedAfterWrite) ++file.id;
    return true;
}
static void SHChangeNotify(DWORD,DWORD,const void*,const void*) { ++notices; }
#include "../../Scripts/FileVisibility.h"
#include "../../Scripts/FileVisibilityText.h"
int main() {
    using namespace JobsFileVisibility;
    unsigned assertions=0;
    const auto expect=[&](bool value,const char* why) { ++assertions; if (!value) throw std::runtime_error(why); };
    for (const auto& path : {L"",L"C:\\",L"C:\\folder\\..",L"relative",L"\\\\server\\share",L"\\\\server\\share\\",L"\\\\.\\C:",L"\\\\?\\C:\\",L"C:\\file:stream"}) expect(!IsPathEligible(path),"root/device/relative/stream excluded");
    for (const auto& path : {L"C:\\中文 !&%[]'.txt",L"C:\\folder",L"\\\\server\\share\\folder"}) expect(IsPathEligible(path),"ordinary absolute path accepted");
    const std::wstring path=L"C:\\中文 !&%[]'.txt";
    files[path].attributes=FILE_ATTRIBUTE_READONLY | FILE_ATTRIBUTE_ARCHIVE | FILE_ATTRIBUTE_SYSTEM | FILE_ATTRIBUTE_COMPRESSED;
    Target target;
    expect(Snapshot(path,target)==ERROR_SUCCESS && !target.hidden,"snapshot visible file");
    const DWORD preserved=files[path].attributes;
    expect(Apply(target,true)==ERROR_SUCCESS,"hide succeeds");
    expect(files[path].attributes==(preserved | FILE_ATTRIBUTE_HIDDEN),"other attributes preserved on hide");
    const size_t previousWrites=writes;
    expect(Apply(target,true)==ERROR_SUCCESS && writes==previousWrites,"hide is idempotent");
    expect(Apply(target,false)==ERROR_SUCCESS && files[path].attributes==preserved,"show restores hidden only");
    files[L"C:\\plain"].attributes=FILE_ATTRIBUTE_NORMAL;
    expect(Snapshot(L"C:\\plain",target)==0 && Apply(target,true)==0 && files[L"C:\\plain"].attributes==FILE_ATTRIBUTE_HIDDEN,"NORMAL never combined with Hidden");
    expect(Apply(target,false)==0 && files[L"C:\\plain"].attributes==FILE_ATTRIBUTE_NORMAL,"empty attributes normalized to NORMAL");
    files[L"C:\\folder"].attributes=FILE_ATTRIBUTE_DIRECTORY;
    files[L"C:\\folder\\child"].attributes=FILE_ATTRIBUTE_ARCHIVE;
    expect(Snapshot(L"C:\\folder",target)==0 && Apply(target,true)==0,"directory hide succeeds");
    expect(files[L"C:\\folder\\child"].attributes==FILE_ATTRIBUTE_ARCHIVE,"directory action does not recurse");
    files[L"C:\\link"].attributes=FILE_ATTRIBUTE_REPARSE_POINT;
    expect(Snapshot(L"C:\\link",target)==ERROR_NOT_SUPPORTED,"link excluded");
    files[L"C:\\device"].attributes=FILE_ATTRIBUTE_DEVICE;
    expect(Snapshot(L"C:\\device",target)==ERROR_NOT_SUPPORTED,"device excluded");
    expect(Snapshot(L"C:\\missing",target)!=0,"missing target rejected");
    files[L"C:\\denied"].denied=true;
    expect(Snapshot(L"C:\\denied",target)!=0,"unreadable target rejected");
    expect(Snapshot(path,target)==0,"replacement fixture snapshotted");
    ++files[path].id;
    expect(Apply(target,true)==ERROR_FILE_INVALID && files[path].attributes==preserved,"replacement rejected before write");
    expect(Snapshot(path,target)==0,"link replacement fixture snapshotted");
    files[path].attributes|=FILE_ATTRIBUTE_REPARSE_POINT;
    expect(Apply(target,true)==ERROR_NOT_SUPPORTED,"late reparse point rejected");
    files[path].attributes=preserved;
    expect(Snapshot(path,target)==0,"write-denied fixture snapshotted");
    files[path].writeFailure=true;
    expect(Apply(target,true)!=0 && files[path].attributes==preserved,"write failure retains attributes");
    files[path].writeFailure=false;
    files[path].replacedAfterWrite=true;
    expect(Apply(target,true)!=0,"post-write identity change reported");
    files[path].replacedAfterWrite=false;
    expect(timestampsUntouched,"timestamp fields stay zero (leave unchanged)");
    expect(noFollow && opened==closed,"every handle has no-follow flag and is closed");
    expect(notices==5,"only successful mutations notify Explorer");
    for (const auto& code : {L"zh-Hans",L"zh-Hant",L"bo",L"en",L"ja",L"fr",L"es",L"de",L"ru",L"ko"}) {
        const auto& text=TextFor(code);
        expect(std::wstring(text.code)==code && std::wstring(text.hide)!=text.show,"all ten locales have distinct actions");
        const auto summary=Summary(text,2,7);
        expect(summary.find(L"{0}")==std::wstring::npos && summary.find(L"{1}")==std::wstring::npos,"localized counts formatted");
    }
    expect(std::wstring(TextFor(L"zh-TW").code)==L"zh-Hant" && std::wstring(TextFor(L"de-DE").code)==L"de","system language mapping");
    std::cout<<"PASS: "<<assertions<<" native visibility assertions\n";
}
