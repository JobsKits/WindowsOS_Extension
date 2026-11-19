# Manage.vbs

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、调用与资源](#jobs-toc-heading-2)
- [二、验证与边界](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

使用 WScript 隐藏启动本包 PowerShell GUI，严格引用参数并保留取消和启动错误；不承担安装业务。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、调用与资源 <a href="#前言">🔼</a> <a href="#🔚">🔽</a></span><!-- jobs-toc:heading-end -->

实际源码：[./Manage.vbs](./Manage.vbs)。正常使用从功能根的 `Manage.cmd` 打开面板，整体保留功能包；后台参数由现有调用者传递，安装 / 更新与卸载均在面板确认。

源码使用同名包装，资源基准从当前脚本推导；发行 release、注册表和旧状态仍保留原平铺文件名。发布复制阶段仅压平本批包装，原有 Clean.ps1 目录和完整清理逻辑不变。支持中文、空格和整体搬迁，不依赖启动工作目录。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、验证与边界 <a href="#前言">🔼</a> <a href="#🔚">🔽</a></span><!-- jobs-toc:heading-end -->

PowerShell 语法、源码 / 旧平铺目录基准、CMD / VBS 寻址夹具和发布资源清单已隔离核对。日志、取消、失败状态及清理确认沿用原实现；未执行真实构建、安装、注册表修改或清理。VBS / CMD 尚未在原生 Windows 宿主执行，隔离路径夹具不冒充原生验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
