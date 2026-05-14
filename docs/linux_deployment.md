# Linux 编译与部署说明

## 目标
将当前源码放到 Linux x86_64 平台后，可以完成依赖配置、CMake 编译、运行配置和部署目录整理。

当前 Linux 构建入口已经在 `CMakePresets.json` 中提供：

- `linux-release`：Linux Release 配置预设
- `pilot-linux-release`：只构建主程序 `PilotApp`

## 推荐环境

- Linux x86_64，推荐 Ubuntu 20.04 / 22.04 / 24.04 或同等发行版
- GCC/G++ 9 或更高版本
- CMake 3.10 或更高版本
- Ninja
- Python 3 开发包
- NVIDIA 驱动；如果使用 GPU 推理，还需要 CUDA / cuDNN 与 ONNX Runtime GPU 版本匹配

基础工具示例：

```bash
sudo apt update
sudo apt install -y build-essential cmake ninja-build pkg-config python3 python3-dev
```

## 依赖项

工程编译需要以下 C++ 依赖：

- FFmpeg 开发库：`libavcodec`、`libavutil`、`libswscale` 等
- OpenCV
- LibTorch
- ONNX Runtime
- libdatachannel
- Python3 development
- pthread

Ubuntu 系统包中可安装一部分基础依赖：

```bash
sudo apt install -y libavcodec-dev libavutil-dev libswscale-dev libopencv-dev
```

`LibTorch`、`ONNX Runtime`、`libdatachannel` 建议单独安装，并在 CMake 配置时指定路径。

## libdatachannel 配置

推荐使用 vcpkg：

```bash
git clone https://github.com/microsoft/vcpkg.git /opt/vcpkg
/opt/vcpkg/bootstrap-vcpkg.sh
/opt/vcpkg/vcpkg install libdatachannel:x64-linux
```

编译前设置：

```bash
export VCPKG_ROOT=/opt/vcpkg
```

如果使用 vcpkg toolchain，可以在配置时增加：

```bash
-DCMAKE_TOOLCHAIN_FILE=/opt/vcpkg/scripts/buildsystems/vcpkg.cmake
```

如果不用 vcpkg，需要保证 CMake 能通过 `CMAKE_PREFIX_PATH` 或系统库路径找到 `LibDataChannel::LibDataChannel`，或者能找到 `libdatachannel.so`。

## ONNX Runtime 配置

默认 Linux preset 假设 ONNX Runtime 位于：

```text
/opt/onnxruntime
```

目录结构应类似：

```text
/opt/onnxruntime/
  include/
  lib/
    libonnxruntime.so
    libonnxruntime_providers_shared.so
    libonnxruntime_providers_cuda.so  # GPU 版本才有
```

如果实际路径不同，配置时传入：

```bash
-DORT_DIR=/path/to/onnxruntime
```

如果只使用 CPU 版本 ONNX Runtime：

```bash
-DPILOT_USE_ORT_CUDA=OFF
```

## LibTorch 配置

假设 LibTorch 解压在：

```text
/opt/libtorch
```

配置时传入：

```bash
-DCMAKE_PREFIX_PATH=/opt/libtorch
```

如果还需要让 CMake 同时找到 vcpkg 包，可以用分号分隔：

```bash
-DCMAKE_PREFIX_PATH="/opt/libtorch;/opt/vcpkg/installed/x64-linux"
```

## 运行配置文件

Linux 下程序优先读取：

```text
config/pilot_deploy.linux.properties
```

找不到时再回退：

```text
config/pilot_deploy.properties
```

当前 Linux 配置模板：

```properties
base_dir=..
client_index=client/index.html
i3d_model=models/a320_new_full.onnx
tridet_model=models/tridet_a320.onnx
yolo_model=models/best.onnx
ffmpeg_path=runtime/ffmpeg/ffmpeg
output_dir=output
temp_dir=temp
host=0.0.0.0
port=8080
gpu_device_id=0
```

常用调整项：

- `base_dir`：部署根目录，默认相对 `config/` 指向上一层
- `client_index`：前端页面路径
- `i3d_model` / `tridet_model` / `yolo_model`：模型路径
- `ffmpeg_path`：FFmpeg 可执行文件路径；如果使用系统 FFmpeg，可改成 `/usr/bin/ffmpeg`
- `output_dir`：报告输出目录
- `temp_dir`：临时帧缓存目录
- `host` / `port`：HTTP 服务监听地址和端口
- `gpu_device_id`：GPU 编号；CPU 运行时建议配合 `-DPILOT_USE_ORT_CUDA=OFF`

## 编译

进入源码根目录：

```bash
cd /path/to/pilot
```

使用默认 Linux preset 配置：

```bash
cmake --preset linux-release \
  -DORT_DIR=/opt/onnxruntime \
  -DCMAKE_PREFIX_PATH="/opt/libtorch;/opt/vcpkg/installed/x64-linux" \
  -DCMAKE_TOOLCHAIN_FILE=/opt/vcpkg/scripts/buildsystems/vcpkg.cmake
```

只构建主程序：

```bash
cmake --build --preset pilot-linux-release
```

如果只使用 CPU 版 ONNX Runtime：

```bash
cmake --preset linux-release \
  -DORT_DIR=/opt/onnxruntime \
  -DCMAKE_PREFIX_PATH="/opt/libtorch;/opt/vcpkg/installed/x64-linux" \
  -DCMAKE_TOOLCHAIN_FILE=/opt/vcpkg/scripts/buildsystems/vcpkg.cmake \
  -DPILOT_USE_ORT_CUDA=OFF

cmake --build --preset pilot-linux-release
```

如果需要构建所有目标：

```bash
cmake --build out/build/linux-release
```

## 构建产物

默认输出目录：

```text
out/build/linux-release/
```

主程序：

```text
out/build/linux-release/pilot
```

其它测试目标在构建对应 target 后也会位于同一目录，例如：

```text
out/build/linux-release/test_runner
out/build/linux-release/test_extractFeatures
out/build/linux-release/test_yolo
```

## 生成可迁移部署目录

Linux 下提供打包脚本：

```bash
scripts/package_linux.sh
```

默认会查找：

```text
out/build/linux-release/pilot
out/build/linux-base/pilot
build/pilot
```

并输出：

```text
dist/pilot_linux/
```

如果构建目录不是默认位置：

```bash
scripts/package_linux.sh --preferred-build-dir /path/to/build-dir
```

如果依赖目录不是默认位置：

```bash
scripts/package_linux.sh \
  --ort-dir /opt/onnxruntime \
  --libtorch-dir /opt/libtorch \
  --vcpkg-root /opt/vcpkg \
  --cuda-root /usr/local/cuda
```

如果 cuDNN 单独安装：

```bash
scripts/package_linux.sh --cudnn-root /path/to/cudnn
```

如果只希望目标机使用系统库，不把 `.so` 打进包：

```bash
scripts/package_linux.sh --skip-so-runtime --skip-cuda-runtime --skip-ldd-runtime
```

脚本默认还会用 `ldd` 收集 `pilot` 依赖的非 glibc/非 NVIDIA 驱动动态库，减少目标机缺少 OpenCV、FFmpeg、libstdc++ 等运行库的概率。NVIDIA 驱动本身仍需要在目标机安装。

打包结果结构：

```text
dist/pilot_linux/
  bin/
    pilot
  client/
    index.html
  config/
    pilot_deploy.linux.properties
  models/
    a320_new_full.onnx
    tridet_a320.onnx
    best.onnx
  runtime/
    ffmpeg/
      ffmpeg
    lib/
      *.so*
  output/
  temp/
  run.sh
  README_DEPLOY.txt
```

迁移到目标机后：

```bash
cd /path/to/pilot_linux
./run.sh
```

## 运行

开发环境中可以直接从源码根目录运行：

```bash
./out/build/linux-release/pilot
```

然后访问：

```text
http://127.0.0.1:8080/
```

如果运行时找不到 `libonnxruntime.so`、`libtorch.so` 或其它 `.so`，设置动态库路径：

```bash
export LD_LIBRARY_PATH=/opt/onnxruntime/lib:/opt/libtorch/lib:/opt/vcpkg/installed/x64-linux/lib:$LD_LIBRARY_PATH
```

再启动：

```bash
./out/build/linux-release/pilot
```

## 部署目录建议

建议整理成如下目录：

```text
pilot_linux/
  bin/
    pilot
  client/
    index.html
  config/
    pilot_deploy.linux.properties
  models/
    a320_new_full.onnx
    tridet_a320.onnx
    best.onnx
  runtime/
    ffmpeg/
      ffmpeg
  output/
  temp/
```

部署后从 `bin/` 启动时，程序会根据可执行文件目录和当前工作目录查找 `config/pilot_deploy.linux.properties`。如果配置文件中使用默认 `base_dir=..`，则 `client/`、`models/`、`runtime/`、`output/`、`temp/` 都应放在部署根目录下。

启动示例：

```bash
cd /path/to/pilot_linux/bin
export LD_LIBRARY_PATH=/opt/onnxruntime/lib:/opt/libtorch/lib:/opt/vcpkg/installed/x64-linux/lib:$LD_LIBRARY_PATH
./pilot
```

## 常见问题

### 找不到 ONNX Runtime

确认 `ORT_DIR` 指向 ONNX Runtime 根目录，而不是 `lib/` 子目录：

```bash
cmake --preset linux-release -DORT_DIR=/opt/onnxruntime
```

### 找不到 LibTorch

确认 `CMAKE_PREFIX_PATH` 包含 LibTorch 根目录：

```bash
-DCMAKE_PREFIX_PATH=/opt/libtorch
```

### 找不到 libdatachannel

确认已安装：

```bash
/opt/vcpkg/vcpkg install libdatachannel:x64-linux
```

并传入：

```bash
-DCMAKE_TOOLCHAIN_FILE=/opt/vcpkg/scripts/buildsystems/vcpkg.cmake
```

### 找不到 FFmpeg 可执行文件

如果没有随包放置 `runtime/ffmpeg/ffmpeg`，将配置改成系统路径：

```properties
ffmpeg_path=/usr/bin/ffmpeg
```

### 服务器无图形界面

Linux preset 默认：

```text
PILOT_ENABLE_LOCAL_WINDOW=OFF
```

因此不会调用 OpenCV 本地窗口显示。前端仍通过 WebRTC 查看分析画面。
