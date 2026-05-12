# Windows 离线部署说明

## 目标
将当前主机上的编译产物、模型、前端静态页和运行时依赖打成一个可复制到另一台 Windows 主机的部署包。

## 生成部署包
在当前开发机运行：

```powershell
.\scripts\package_windows.ps1
```

默认会自动查找 `pilot\x64\Debug`、`pilot\x64\Release`、`out\build\windows-release`、`out\build\windows-base` 中的 `pilot.exe`，并输出到 `dist/pilot_windows/`。

如果要手动指定构建产物目录：

```powershell
.\scripts\package_windows.ps1 -PreferredBuildDir "out\build\windows-release"
```

如需手动指定 VS/CUDA/cuDNN 来源：

```powershell
.\scripts\package_windows.ps1 -MsvcRedistRoot "D:\Visual Studio\VC\Redist\MSVC" -CudaRoot $env:CUDA_PATH -CudnnRoot "C:\Program Files\NVIDIA\CUDNN\v9.19\bin\12.9\x64"
```

## 目标机目录结构
- `bin/pilot.exe`
- `client/index.html`
- `config/pilot_deploy.properties`
- `models/*.onnx`
- `runtime/ffmpeg/ffmpeg.exe`
- `runtime/*.dll`
- `output/`
- `temp/`

## 启动方式
在目标机上直接运行：

```powershell
.\bin\pilot.exe
```

然后访问：

```text
http://127.0.0.1:8080/
```

## 目标机要求
- Windows x64，带桌面会话
- NVIDIA 驱动
- 端口 `8080` 未被其他程序占用，且防火墙允许访问
- 若打包时未找到 MSVC runtime，则需要在目标机安装 VC++ Redistributable
- 若打包时未找到 CUDA / cuDNN runtime，则需要在目标机安装兼容版本
- 若 `runtime/ffmpeg/ffmpeg.exe` 不存在，则需保证 `ffmpeg.exe` 在 `PATH`

## 当前打包策略
- 优先打包 Release 类构建产物
- `bin/` 和 `runtime/` 中都会放入启动所需 DLL，便于直接从 `bin/pilot.exe` 启动
- 发现 MSVC runtime 时自动拷贝
- 发现 CUDA / cuDNN runtime 时自动拷贝
- 目标机仍必须安装 NVIDIA 显卡驱动，驱动本身不能随包替代

## 调整项
如需改端口、模型路径或输出目录，修改 `config/pilot_deploy.properties`。
