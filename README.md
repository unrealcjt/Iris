# Iris

<!-- <table>
  <tr>
    <td valign="bottom">
      <img src="assets/img/Iris_female.png" width="350">
    </td>
    <td valign="bottom">
      <video src="https://github.com/user-attachments/assets/f033806d-efb3-4e32-8823-d2f4f3141ca6" width="350" controls>
        您的浏览器不支持视频标签。
      </video>
    </td>
  </tr>
</table> -->
<p align="center">
  <img src="assets/img/Iris_Hi.png" width="500" alt="Iris">
</p>
<p align="center"><strong>App看板娘Iris</strong></p>

## 简介
一个基于大模型构建的语言学习纯flutter项目，使用Google的Gemma4端侧模型，可离线调用。

由于本人手机上没有稳定的魔法，所以无法测试使用网络自动下载，仅提供本地文件加载模型，可以自行下载Gemma4-e2b和e4b模型

https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm

https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm

最好两个都下，有些功能e2b效果不太行，有些功能e4b模型又有点慢，导入两个随时切换，"我的->模型配置"里可以从手机本地添加模型到app文件目录。

App接入Jmdict日语词典，位置应该位于assets目录下，需要运行项目代码本地构建时，可自行下载https://github.com/seanmcbroom/JMdictSQLite 最新版本

如果需要直接使用，请下载 [Release](https://github.com/unrealcjt/Iris/releases/latest/download/app-arm64-v8a-release.apk) 版本。

目前仅支持CPU调用（作者本人手机配置不足，等哪天换手机考虑新增GPU调用）

