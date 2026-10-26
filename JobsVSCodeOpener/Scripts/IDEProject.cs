// IDEProject.cs | Jobs IDE directory eligibility
// Created by Jobs on 2026年10月26日，星期一.
using System;
using System.Collections.Generic;
using System.Text;
using System.IO;
using System.Text.RegularExpressions;
namespace Jobs {
    public static class IDEProject {
        private static int Kind(string path) {
            try {
                FileAttributes attributes = File.GetAttributes(path);
                if ((attributes & FileAttributes.ReparsePoint) != 0) return 2;
                DirectoryInfo parent = (attributes & FileAttributes.Directory) != 0 ? Directory.GetParent(path) : new FileInfo(path).Directory;
                while (parent != null) {
                    if ((parent.Attributes & FileAttributes.ReparsePoint) != 0) return 2;
                    parent = parent.Parent;
                }
                return (attributes & FileAttributes.Directory) != 0 ? 1 : 0;
            } catch (FileNotFoundException) { return -1; }
            catch (DirectoryNotFoundException) { return -1; }
            catch { return 2; }
        }
        private static string Read(string path) {
            if (Kind(path) != 0 || new FileInfo(path).Length > 1048576) return "";
            return File.ReadAllText(path);
        }
        private static bool FileAt(string path, string name) { return Kind(Path.Combine(path, name)) == 0; }
        private static string[] Entries(string path) {
            List<string> entries = new List<string>();
            foreach (string entry in Directory.EnumerateFileSystemEntries(path)) {
                entries.Add(entry);
            }
            return entries.ToArray();
        }
        private static bool AndroidPlugin(string text) {
            StringBuilder source = new StringBuilder();
            char quote = '\0';
            for (int index = 0; index < text.Length; index++) {
                char value = text[index];
                if (quote != '\0') {
                    source.Append(value);
                    if (value == '\\' && index + 1 < text.Length) source.Append(text[++index]);
                    else if (value == quote) quote = '\0';
                } else if (value == '/' && index + 1 < text.Length && text[index + 1] == '/') {
                    while (index < text.Length && text[index] != '\n') index++;
                    source.Append('\n');
                } else if (value == '/' && index + 1 < text.Length && text[index + 1] == '*') {
                    int end = text.IndexOf("*/", index + 2, StringComparison.Ordinal);
                    if (end < 0) break;
                    index = end + 1;
                    source.Append(' ');
                } else {
                    source.Append(value);
                    if (value == '\'' || value == '"') quote = value;
                }
            }
            return Regex.IsMatch(source.ToString(), @"(id\s*\(?\s*|apply\s+plugin\s*:\s*|apply\s*\(\s*plugin\s*=\s*)[""']com\.android\.(application|library|dynamic-feature|test)[""']|alias\s*\(\s*libs\.plugins\.android[.A-Za-z0-9_]*\s*\)|classpath\s*\(?\s*[""']com\.android\.tools\.build:gradle");
        }
        private static bool Android(string path, bool flutter) {
            if (flutter) return true;
            if (!FileAt(path, "settings.gradle") && !FileAt(path, "settings.gradle.kts")) return false;
            foreach (string name in new string[] { "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts", "app/build.gradle", "app/build.gradle.kts" }) {
                string text = Read(Path.Combine(path, name));
                if (AndroidPlugin(text)) return true;
            }
            bool rootBuild = FileAt(path, "build.gradle") || FileAt(path, "build.gradle.kts");
            if (rootBuild && (FileAt(path, "AndroidManifest.xml") || FileAt(path, "src/main/AndroidManifest.xml"))) return true;
            bool appBuild = FileAt(path, "app/build.gradle") || FileAt(path, "app/build.gradle.kts");
            return appBuild && FileAt(path, "app/src/main/AndroidManifest.xml");
        }
        private static string IOSMetadata(string path) {
            int kind = Kind(path);
            if (kind == -1) return null;
            if (kind != 0 || new FileInfo(path).Length > 1048576) throw new IOException("Cannot classify iOS metadata reliably");
            return File.ReadAllText(path);
        }
        private static bool IOSProject(string path) {
            int kind = Kind(path);
            if (kind == 2) throw new IOException("Cannot classify linked or inaccessible project");
            if (kind != 1) return false;
            string source = IOSMetadata(Path.Combine(path, "project.pbxproj"));
            return source != null && Regex.IsMatch(source, @"(SDKROOT\s*=\s*""?iphone(os|simulator)|SUPPORTED_PLATFORMS\s*=\s*""?[^;]*iphone(os|simulator))");
        }
        private static bool IOSAt(string path) {
            if (Kind(path) != 1) return false;
            foreach (string entry in Entries(path)) {
                if (entry.EndsWith(".xcodeproj", StringComparison.OrdinalIgnoreCase) && IOSProject(entry)) return true;
                if (!entry.EndsWith(".xcworkspace", StringComparison.OrdinalIgnoreCase)) continue;
                int kind = Kind(entry);
                if (kind == 2) throw new IOException("Cannot classify linked or inaccessible workspace");
                if (kind != 1) continue;
                string workspace = IOSMetadata(Path.Combine(entry, "contents.xcworkspacedata"));
                if (workspace == null) continue;
                foreach (Match match in Regex.Matches(workspace, @"location\s*=\s*[""'](group|container|absolute):([^""']+\.xcodeproj)[""']", RegexOptions.IgnoreCase)) {
                    string relative = match.Groups[2].Value.Replace("&amp;", "&").Replace("&quot;", "\"").Replace("&apos;", "'").Replace("&lt;", "<").Replace("&gt;", ">");
                    string resolved = String.Equals(match.Groups[1].Value, "absolute", StringComparison.OrdinalIgnoreCase) ? Path.GetFullPath(relative) : Path.GetFullPath(Path.Combine(path, relative.Replace('/', Path.DirectorySeparatorChar)));
                    if (Kind(resolved) != 1) throw new IOException("Workspace project reference is unresolved");
                    if (IOSProject(resolved)) return true;
                }
            }
            return false;
        }
        public static bool Eligible(string path, string ide, bool flutter) {
            try {
                if (Kind(path) != 1) return false;
                bool hasContent = false;
                foreach (string entry in Entries(path)) {
                    string name = Path.GetFileName(entry).ToLowerInvariant();
                    if (name != ".ds_store" && name != "thumbs.db" && name != "desktop.ini") { hasContent = true; break; }
                }
                if (!hasContent) return false;
                string extension = Path.GetExtension(path.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)).ToLowerInvariant();
                if (Array.IndexOf(new string[] { ".app", ".xcodeproj", ".xcworkspace", ".bundle", ".framework" }, extension) >= 0) return false;
                if (ide == "android-studio") return Android(path, flutter);
                if (ide != "vscode") return false;
                if (flutter) return true;
                return !IOSAt(path);
            } catch { return false; }
        }
    }
}
