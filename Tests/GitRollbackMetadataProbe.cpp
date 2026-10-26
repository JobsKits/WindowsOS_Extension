// GitRollbackMetadataProbe.cpp | portable metadata gate tests
// Created by Jobs on 2026年10月26日，星期一.
#include "../JobsGitRollback/Scripts/GitRepository.h"
#include <map>
#include <iostream>
#include <stdexcept>

struct Fixture {
    std::map<std::wstring,int> types;
    std::map<std::wstring,std::wstring> content;
    int assertions = 0;
    static std::wstring Absolute(const std::wstring& path) {
        std::vector<std::wstring> parts;
        std::wstring piece;
        for (size_t i = 0; i <= path.size(); ++i) {
            const auto c = i == path.size() ? L'\\' : path[i];
            if (c != L'\\' && c != L'/') { piece += c; continue; }
            if (piece == L"..") { if (parts.size() <= 1) return L""; parts.pop_back(); }
            else if (!piece.empty() && piece != L".") parts.push_back(piece);
            piece.clear();
        }
        std::wstring result;
        for (const auto& part : parts) result += (result.empty() ? L"" : L"\\") + part;
        if (result.size() == 2) result += L"\\";
        return result;
    }
    void File(const std::wstring& path, const std::wstring& data) { types[path] = 0; content[path] = data; }
    void Directory(const std::wstring& path) { types[path] = 1; }
    void Repository(const std::wstring& root) {
        Directory(root);
        const auto metadata = root + L"\\.git";
        Directory(metadata); Directory(metadata + L"\\objects"); Directory(metadata + L"\\refs");
        File(metadata + L"\\config", L"[core]"); File(metadata + L"\\HEAD", L"ref: refs/heads/main\n");
    }
    JobsGit::Files Files() {
        return {
            [this](const std::wstring& path) { auto at=types.find(path); return at==types.end() ? -1 : at->second; },
            [this](const std::wstring& path,std::wstring& value) { auto at=content.find(path); if(at==content.end())return false;value=at->second;return true; },
            Absolute
        };
    }
    void Check(const std::wstring& path,bool expected,const char* label) {
        ++assertions;
        if (JobsGit::WorkingTree(Files(),path) != expected) throw std::runtime_error(label);
    }
};
int main() {
    Fixture f;
    f.Directory(L"C:\\"); f.Directory(L"C:\\ordinary");
    f.Check(L"C:\\ordinary",false,"ordinary hidden");
    f.Repository(L"C:\\repo");
    f.Check(L"C:\\repo",true,"root shown");
    f.Directory(L"C:\\repo\\src");
    f.Check(L"C:\\repo\\src",true,"internal directory shown");
    f.Check(L"C:\\repo\\.git",false,"metadata hidden");
    f.Check(L"C:\\repo\\.git\\objects",false,"metadata internals hidden");
    f.File(L"C:\\repo\\src\\.git",L"malformed");
    f.Check(L"C:\\repo\\src",false,"malformed inner gitfile blocks parent");
    f.types.erase(L"C:\\repo\\src\\.git");
    f.Repository(L"C:\\repo\\src");
    f.Check(L"C:\\repo\\src",true,"independent inner repository shown");
    f.File(L"C:\\repo\\src\\.git\\HEAD",L"invalid");
    f.Check(L"C:\\repo\\src",false,"malformed inner gitdir blocks parent");
    f.types[L"C:\\repo\\src\\.git"] = 2;
    f.Check(L"C:\\repo\\src",false,"symlink gitdir hidden");
    f.Directory(L"C:\\sub");
    f.File(L"C:\\sub\\.git",L"gitdir: ../repo/.git\n");
    f.Check(L"C:\\sub",true,"relative gitfile shown");
    f.File(L"C:\\sub\\.git",L"gitdir: C:repo");
    f.Check(L"C:\\sub",false,"drive-relative gitfile rejected");
    f.File(L"C:\\sub\\.git",L"gitdir: \\\\server\\repo");
    f.Check(L"C:\\sub",false,"UNC gitfile rejected");
    f.File(L"C:\\sub\\.git",L"gitdir: /repo");
    f.Check(L"C:\\sub",false,"rooted drive-ambiguous gitfile rejected");
    f.Directory(L"C:\\worktree");
    f.Directory(L"C:\\repo\\.git\\worktrees\\a");
    f.File(L"C:\\repo\\.git\\worktrees\\a\\HEAD",L"ref: refs/heads/linked");
    f.File(L"C:\\repo\\.git\\worktrees\\a\\commondir",L"../..");
    f.File(L"C:\\worktree\\.git",L"gitdir: C:\\repo\\.git\\worktrees\\a");
    f.Check(L"C:\\worktree",true,"worktree commondir shown");
    f.File(L"C:\\repo\\.git\\worktrees\\a\\commondir",L"../../missing");
    f.Check(L"C:\\worktree",false,"missing common hidden");
    f.File(L"C:\\repo\\.git\\HEAD",std::wstring(40,L'a'));
    f.Check(L"C:\\repo",true,"detached metadata valid but execution checks branch");
    f.File(L"C:\\repo\\.git\\HEAD",L"ref: refs/heads/../main");
    f.Check(L"C:\\repo",false,"malformed HEAD hidden");
    f.File(L"C:\\repo\\.git\\HEAD",L"ref: refs/heads/main\nextra");
    f.Check(L"C:\\repo",false,"multiline HEAD hidden");
    f.Repository(L"C:\\reftable");
    f.types.erase(L"C:\\reftable\\.git\\refs");
    f.Directory(L"C:\\reftable\\.git\\reftable");
    f.Check(L"C:\\reftable",true,"reftable reference storage shown");
    f.types[L"C:\\repo"] = 2;
    f.Check(L"C:\\repo",false,"nonordinary target hidden");
    f.File(L"C:\\file",L"x"); f.Check(L"C:\\file",false,"file target hidden");
    f.Check(L"",false,"empty hidden");
    std::cout << "PASS GitRollbackMetadataProbe: " << f.assertions << " assertions\n";
}
