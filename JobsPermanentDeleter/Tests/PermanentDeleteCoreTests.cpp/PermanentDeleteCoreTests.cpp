// PermanentDeleteCoreTests.cpp | JobsPermanentDeleter
// Created by Jobs on 2026年11月18日，星期三.
// Production deletion plan, with an in-memory Win32 boundary; never deletes host files.
#include <algorithm>
#include <cstdint>
#include <cwchar>
#include <cstring>
#include <iostream>
#include <map>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>
using DWORD=uint32_t; using UINT=uint32_t; using HANDLE=void*;
constexpr HANDLE INVALID_HANDLE_VALUE=nullptr;
constexpr DWORD ERROR_SUCCESS=0,ERROR_ACCESS_DENIED=5,ERROR_FILE_NOT_FOUND=2,ERROR_NO_MORE_FILES=18,
 ERROR_NOT_SUPPORTED=50,ERROR_INVALID_NAME=123,ERROR_DIRECTORY=267,ERROR_FILE_INVALID=1006,
 ERROR_INVALID_PARAMETER=87,ERROR_BUFFER_OVERFLOW=111,ERROR_DIR_NOT_EMPTY=145;
constexpr DWORD FILE_ATTRIBUTE_READONLY=1,FILE_ATTRIBUTE_DIRECTORY=16,FILE_ATTRIBUTE_REPARSE_POINT=1024,FILE_ATTRIBUTE_DEVICE=64,
 FILE_READ_ATTRIBUTES=128,FILE_LIST_DIRECTORY=1,FILE_SHARE_READ=1,FILE_SHARE_WRITE=2,FILE_SHARE_DELETE=4,
 OPEN_EXISTING=3,FILE_FLAG_BACKUP_SEMANTICS=0x2000000,FILE_FLAG_OPEN_REPARSE_POINT=0x200000,DELETE=0x10000,
 FILE_NAME_NORMALIZED=0,VOLUME_NAME_DOS=0;
constexpr int TRUE=1,FileDispositionInfo=4;
struct BY_HANDLE_FILE_INFORMATION { DWORD dwFileAttributes=0,dwVolumeSerialNumber=1,nFileIndexHigh=0,nFileIndexLow=1; };
struct FILE_DISPOSITION_INFO { int DeleteFile; };
struct WIN32_FIND_DATAW { DWORD dwFileAttributes=0; wchar_t cFileName[260]={}; };
struct File { DWORD attributes=0,id=0; bool deny=false,disposed=false,deleted=false,deleteFailure=false; std::wstring alias; };
struct Open { std::wstring path; File* file; DWORD access,share; };
struct Search { std::vector<std::wstring> children; size_t index=0; };
static std::map<std::wstring,File> files;
static DWORD lastError=ERROR_SUCCESS,nextId=1;
static size_t deletes=0,opened=0,closed=0;
static bool noFollow=true,pinned=true;
static int _wcsicmp(const wchar_t*a,const wchar_t*b) { return wcscasecmp(a,b); }
static int _wcsnicmp(const wchar_t*a,const wchar_t*b,size_t n) { return wcsncasecmp(a,b,n); }
static DWORD GetLastError() { return lastError; }
static DWORD Copy(const std::wstring& value,DWORD length,wchar_t* output) {
 if (!length||value.size()>=length) return static_cast<DWORD>(value.size()+1);
 std::copy(value.begin(),value.end(),output); output[value.size()]=0; return static_cast<DWORD>(value.size());
}
static std::wstring Canonical(std::wstring value) {
 std::replace(value.begin(),value.end(),L'/',L'\\');
 if (value.size()<3) return value;
 std::vector<std::wstring> parts;
 size_t pos=3;
 while(pos<value.size()) { size_t end=value.find(L'\\',pos); auto part=value.substr(pos,end==std::wstring::npos?end:end-pos); if(part==L"..") { if(!parts.empty())parts.pop_back(); } else if(part!=L"."&&!part.empty())parts.push_back(part); if(end==std::wstring::npos)break; pos=end+1; }
 std::wstring full=value.substr(0,3); for(size_t i=0;i<parts.size();++i) { if(i)full+=L'\\'; full+=parts[i]; } return full;
}
static DWORD GetFullPathNameW(const wchar_t*path,DWORD n,wchar_t*out,void*) { return Copy(Canonical(path),n,out); }
static UINT GetWindowsDirectoryW(wchar_t*out,UINT n) { return Copy(L"C:\\Windows",n,out); }
static DWORD GetEnvironmentVariableW(const wchar_t*name,wchar_t*out,DWORD n) {
 std::wstring key(name),value;
 if(key==L"USERPROFILE")value=L"C:\\Users\\Jobs";
 else if(key==L"ProgramFiles")value=L"C:\\Program Files";
 else if(key==L"ProgramData")value=L"C:\\ProgramData";
 return value.empty()?0:Copy(value,n,out);
}
static HANDLE CreateFileW(const wchar_t*path,DWORD access,DWORD share,void*,DWORD,DWORD flags,void*) {
 noFollow=noFollow&&((flags&FILE_FLAG_OPEN_REPARSE_POINT)!=0);
 if(access&DELETE)pinned=pinned&&share==FILE_SHARE_READ;
 auto found=files.find(path);
 if(found==files.end()||found->second.deleted) { lastError=ERROR_FILE_NOT_FOUND; return nullptr; }
 if(found->second.deny) { lastError=ERROR_ACCESS_DENIED; return nullptr; }
 ++opened; return new Open{path,&found->second,access,share};
}
static bool CloseHandle(HANDLE value) { auto*o=static_cast<Open*>(value); if(o->file->disposed)o->file->deleted=true; delete o; ++closed; return true; }
static bool GetFileInformationByHandle(HANDLE value,BY_HANDLE_FILE_INFORMATION*out) {
 auto*o=static_cast<Open*>(value); out->dwFileAttributes=o->file->attributes; out->nFileIndexLow=o->file->id; return true;
}
static DWORD GetFinalPathNameByHandleW(HANDLE value,wchar_t*out,DWORD n,DWORD) {
 auto*o=static_cast<Open*>(value); return Copy(L"\\\\?\\"+(o->file->alias.empty()?o->path:o->file->alias),n,out);
}
static bool SetFileInformationByHandle(HANDLE value,int,FILE_DISPOSITION_INFO*info,size_t) {
 auto*o=static_cast<Open*>(value);
 if(!(o->access&DELETE)||!info->DeleteFile||o->file->deleteFailure) { lastError=ERROR_ACCESS_DENIED; return false; }
 if(o->file->attributes&FILE_ATTRIBUTE_DIRECTORY) {
  for(const auto&item:files)if(!item.second.deleted&&item.first.find(o->path+L"\\")==0) { lastError=ERROR_DIR_NOT_EMPTY; return false; }
 }
 ++deletes; o->file->disposed=true; return true;
}
static void CopyFound(const std::wstring&path,WIN32_FIND_DATAW*out) {
 out->dwFileAttributes=files.at(path).attributes;
 auto name=path.substr(path.find_last_of(L'\\')+1); Copy(name,260,out->cFileName);
}
static HANDLE FindFirstFileW(const wchar_t*pattern,WIN32_FIND_DATAW*out) {
 std::wstring prefix(pattern); prefix.erase(prefix.size()-1);
 auto*s=new Search;
 for(const auto&item:files)if(!item.second.deleted&&item.first.find(prefix)==0&&item.first.find(L'\\',prefix.size())==std::wstring::npos)s->children.push_back(item.first);
 if(s->children.empty()) { delete s; lastError=ERROR_FILE_NOT_FOUND; return nullptr; }
 CopyFound(s->children[0],out); return s;
}
static bool FindNextFileW(HANDLE value,WIN32_FIND_DATAW*out) {
 auto*s=static_cast<Search*>(value); if(++s->index>=s->children.size()) { lastError=ERROR_NO_MORE_FILES; return false; }
 CopyFound(s->children[s->index],out); return true;
}
static bool FindClose(HANDLE value) { delete static_cast<Search*>(value); return true; }
#include "../../Scripts/PermanentDelete.h"
#include "../../Scripts/DeleteText.h"
static void Add(const std::wstring&path,DWORD attributes=0) { File file; file.attributes=attributes; file.id=nextId++; files[path]=file; }
static void Reset() {
 if(opened!=closed)throw std::runtime_error("unclosed handles in previous scenario");
 files.clear(); deletes=0;
 for(auto*path:{L"C:\\",L"C:\\Users",L"C:\\Users\\Jobs",L"C:\\Users\\Jobs\\Temp"})Add(path,FILE_ATTRIBUTE_DIRECTORY);
 Add(L"C:\\Users\\Jobs\\Temp\\folder",FILE_ATTRIBUTE_DIRECTORY);
 Add(L"C:\\Users\\Jobs\\Temp\\folder\\中文 !&%[]'.txt");
 Add(L"C:\\Users\\Jobs\\Temp\\folder\\nested",FILE_ATTRIBUTE_DIRECTORY);
 Add(L"C:\\Users\\Jobs\\Temp\\folder\\nested\\child");
}
int main() {
 using namespace JobsPermanentDeleter;
 unsigned checks=0;
 auto expect=[&](bool value,const char*message) { ++checks; if(!value)throw std::runtime_error(message); };
 const std::wstring root=L"C:\\Users\\Jobs\\Temp\\folder",child=root+L"\\nested\\child";
 for(auto*path:{L"",L"C:\\",L"C:\\folder\\..",L"relative",L"\\\\server\\share\\file",L"\\\\?\\C:\\file",L"C:\\file:stream",L"C:\\name. ",L"C:\\name."}) { std::wstring out; expect(Normalize(path,out)!=0,"invalid namespace rejected"); }
 for(auto*path:{L"C:\\Windows",L"C:\\Windows\\System32",L"C:\\Users",L"C:\\Users\\Jobs",L"C:\\Program Files",L"C:\\Program Files\\App",L"C:\\ProgramData\\App"})expect(Protected(path),"protected tree/root rejected");
 expect(!Protected(root),"ordinary profile descendant accepted");
 Reset(); Target target;
 expect(Snapshot(root,target)==0,"snapshot ordinary root");
 { Plan plan; expect(Prepare({target},plan)==0&&plan.entries.size()==4,"all descendants pinned before preview"); expect(Commit(plan,false).deleted==0&&deletes==0,"cancel causes no delete calls"); }
 expect(!files[root].deleted&&!files[child].deleted,"cancel releases objects intact");
 { Plan plan; expect(Prepare({target},plan)==0,"plan can be reopened after cancellation"); auto result=Commit(plan,true); expect(result.error==0&&result.deleted==4,"confirmed plan deletes in postorder"); expect(files[root].deleted&&files[child].deleted,"root and nested child removed"); expect(Commit(plan,true).error!=0,"plan cannot be replayed"); }
 Reset(); expect(Snapshot(root,target)==0,"dedup root snapshot"); Target nested; expect(Snapshot(child,nested)==0,"dedup child snapshot");
 { Plan plan; expect(Prepare({nested,target,target},plan)==0&&plan.roots.size()==1&&plan.entries.size()==4,"overlapping and duplicate selections collapse"); }
 Reset(); Snapshot(root,target); ++files[root].id;
 { Plan plan; expect(Prepare({target},plan)==ERROR_FILE_INVALID&&deletes==0,"root identity replacement rejected before confirmation"); expect(Commit(plan,true).error!=0&&deletes==0,"failed plan cannot commit"); }
 Reset(); Snapshot(root,target); files[root].attributes|=FILE_ATTRIBUTE_REPARSE_POINT;
 { Plan plan; expect(Prepare({target},plan)==ERROR_NOT_SUPPORTED&&deletes==0,"root reparse swap rejected"); }
 Reset(); Snapshot(root,target); files[L"C:\\Users\\Jobs\\Temp"].attributes|=FILE_ATTRIBUTE_REPARSE_POINT;
 { Plan plan; expect(Prepare({target},plan)==ERROR_NOT_SUPPORTED&&deletes==0,"ancestor junction rejected"); }
 Reset(); Snapshot(root,target); files[child].attributes|=FILE_ATTRIBUTE_REPARSE_POINT;
 { Plan plan; expect(Prepare({target},plan)==ERROR_NOT_SUPPORTED&&deletes==0,"nested link rejects entire plan without partial deletion"); }
 Reset(); Snapshot(root,target); files[child].attributes|=FILE_ATTRIBUTE_READONLY;
 { Plan plan; expect(Prepare({target},plan)==ERROR_ACCESS_DENIED&&deletes==0,"readonly descendants preserved with no attribute clearing"); }
 Reset(); Snapshot(root,target); files[child].deny=true;
 { Plan plan; expect(Prepare({target},plan)!=0&&deletes==0,"permission failure preserves complete selection"); }
 Reset(); files[root].alias=L"C:\\Program Files\\App"; expect(Snapshot(root,target)==ERROR_INVALID_NAME,"short alias cannot bypass protection");
 Reset(); Add(L"Z:\\file"); files[L"Z:\\file"].alias=L"C:\\Users\\Jobs"; expect(Snapshot(L"Z:\\file",target)==ERROR_INVALID_NAME,"SUBST alias cannot bypass profile protection");
 Reset(); Snapshot(root,target); files[L"C:\\Users\\Jobs\\Temp"].alias=L"C:\\Windows";
 { Plan plan; expect(Prepare({target},plan)==ERROR_INVALID_NAME&&deletes==0,"ancestor alias rejected"); }
 Reset(); Snapshot(root,target);
 { Plan plan; expect(Prepare({target},plan)==0,"concurrency fixture pinned"); Add(root+L"\\new-after-dialog"); auto result=Commit(plan,true); expect(result.error==ERROR_DIR_NOT_EMPTY&&result.deleted==3,"new children cause safe partial failure"); expect(!files[root+L"\\new-after-dialog"].deleted&&!files[root].deleted,"unapproved new child and containing root preserved"); }
 Reset(); Snapshot(root,target);
 { Plan plan; expect(Prepare({target},plan)==0,"late failure fixture pinned"); const auto failedPath=plan.entries.back()->target.path; files[failedPath].deleteFailure=true; auto result=Commit(plan,true); expect(result.error!=0&&result.deleted==0&&result.failedPath==failedPath,"native delete failure returns precise path and count"); }
 Reset(); Snapshot(root,target);
 { Plan plan; expect(Prepare({target},plan)==0,"late identity fixture pinned"); ++files[plan.entries.back()->target.path].id; expect(Commit(plan,true).error==ERROR_FILE_INVALID&&deletes==0,"identity verified on pinned handles before delete"); }
 Reset(); Snapshot(root,target);
 { Plan plan; expect(Prepare({},plan)!=0&&Prepare(std::vector<Target>(129,target),plan)!=0,"empty and excessive selections rejected"); }
 Reset(); Snapshot(root,target);
 for(int i=0;i<4096;++i)Add(root+L"\\file"+std::to_wstring(i));
 { Plan plan; expect(Prepare({target},plan)==ERROR_BUFFER_OVERFLOW&&deletes==0,"handle-count cap rejects oversized tree before confirmation"); }
 for(auto*code:{L"zh-Hans",L"zh-Hant",L"bo",L"en",L"ja",L"fr",L"es",L"de",L"ru",L"ko"}) { const auto&t=TextFor(code); expect(std::wstring(t.code)==code,"all ten locales mapped"); expect(wcslen(t.warning)>10&&wcslen(t.confirm)>0&&wcslen(t.cancel)>0,"localized confirmation warning complete"); }
 expect(std::wstring(TextFor(L"zh-HK").code)==L"zh-Hant"&&std::wstring(TextFor(L"fr-FR").code)==L"fr","system locale mapping");
 expect(opened==closed&&noFollow&&pinned,"all handles closed, no-follow and delete sharing guards retained");
 std::cout<<"PASS: "<<checks<<" permanent-delete core assertions\n";
}
