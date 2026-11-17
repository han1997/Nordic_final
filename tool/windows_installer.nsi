; Nordic 的 Windows 安装包 —— 由 tool/build.sh windows 调起,不单独手打。
;
; 为什么要有这一份:窗口 zip(`Nordic-<版本>-windows-x64.zip`)解压出来能跑,但它
; 不落任何「装了什么、哪一版」的地方 —— 用户从「添加或删除程序」里看到的是一片
; 空白,出了新版也只能自己找地方解压覆盖。安装包把这三件事补上:装进一个固定位置、
; 在卸载项里写清版本、卸载时收拾干净。
;
; **版本不写在这里**。安装包的版本是构建期从 `pubspec.yaml` 读出来、经
; `/DVERSION=` 注进来的(与 apk / zip 的产物名同一条口径:版本的真值只有
; `pubspec.yaml` 那一行)。所以在 `tool/` 之外看到一行硬编码的 `1.0.x` 都是错的。
;
; 传进来的东西(全由 tool/build.sh 从 pubspec.yaml 算出来):
;   /DVERSION=1.0.68+69     给人看的完整版本(卸载项、右键属性里都是它)
;   /DVERSION4=1.0.68.69    四段数字,Windows 的版本资源只认这个形状
;   /DAPPDIR=<绝对路径>     `flutter build windows` 出来的 Release 目录
;   /DOUTFILE=<绝对路径>    要落的 setup.exe
;   /DAPP_SIZE_KB=12345     整目录的 KB 数,写进卸载项(别让系统去数)

Unicode true

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"

!ifndef VERSION
  !error "缺 /DVERSION —— 版本真值在 pubspec.yaml,由 tool/build.sh 注进来"
!endif
!ifndef VERSION4
  !error "缺 /DVERSION4 —— Windows 的版本资源要四段数字,由 tool/build.sh 从 VERSION 拆"
!endif
!ifndef APPDIR
  !error "缺 /DAPPDIR —— 指 flutter build windows 的 Release 目录"
!endif
!ifndef OUTFILE
  !error "缺 /DOUTFILE —— 要落的 setup.exe 全路径"
!endif
!ifndef APP_SIZE_KB
  !define APP_SIZE_KB 0
!endif

!define APP_NAME "Nordic"
!define APP_EXE "nordic.exe"
!define APP_ID "Nordic"
!define APP_PUBLISHER "fun.han1997"
!define APP_URL "https://github.com/han1997/Nordic_final"

Name "${APP_NAME}"
OutFile "${OUTFILE}"
InstallDir "$LOCALAPPDATA\Programs\${APP_NAME}"
InstallDirRegKey HKCU "Software\${APP_ID}" "InstallDir"
; **按用户装**:不弹 UAC、不写 Program Files、卸载也不需要管理员。一个播放器
; 没有理由要系统级权限,而「装不上,因为管理员密码想不起来」是真实会发生的。
RequestExecutionLevel user
SetCompressor /SOLID lzma

!define MUI_ABORTWARNING
; 路径是相对 .nsi 自己(即 `tool/`)算的,makensis 会把脚本所在目录当基准 ——
; 所以别再写 `${__FILEDIR__}`,那会变成 `tool\tool\..`。
!define MUI_ICON "..\windows\runner\resources\app_icon.ico"
!define MUI_UNICON "..\windows\runner\resources\app_icon.ico"
!define MUI_FINISHPAGE_RUN "$INSTDIR\${APP_EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "现在打开 Nordic"
!define MUI_FINISHPAGE_LINK "项目主页"
!define MUI_FINISHPAGE_LINK_LOCATION "${APP_URL}"

!insertmacro MUI_PAGE_WELCOME
; 目录页离开时验一遍 —— 校验函数见下面 `ValidateInstallDir`。
!define MUI_PAGE_CUSTOMFUNCTION_LEAVE ValidateInstallDir
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "SimpChinese"

; 让 setup.exe 自己带着版本 —— 右键属性、「数字签名」页旁边那一栏、
; 以及某些部署工具都是从这儿读的。也是 build.sh 事后唯一能核对的东西。
VIProductVersion "${VERSION4}"
VIAddVersionKey /LANG=2052 "ProductName" "${APP_NAME}"
VIAddVersionKey /LANG=2052 "ProductVersion" "${VERSION}"
VIAddVersionKey /LANG=2052 "FileDescription" "Nordic 安装程序"
VIAddVersionKey /LANG=2052 "FileVersion" "${VERSION}"
VIAddVersionKey /LANG=2052 "CompanyName" "${APP_PUBLISHER}"
VIAddVersionKey /LANG=2052 "LegalCopyright" "${APP_PUBLISHER}"

; 安装前必须过的两道闸(函数本体在 windows_installer_guard.nsh —— 拆出去是为了
; 能被单独测,理由写在那个文件开头)。这里只说什么时候调用:
;   · `.onInit` —— 静默安装没有页面,只有这一处会跑;
;   · 目录页的 LEAVE 回调 —— 用户改过目录之后。
!include "windows_installer_guard.nsh"

Function .onInit
  ; 静默安装(`/S`)没有页面,LEAVE 回调不会跑 —— 闸必须在这儿再走一遍,否则
  ; 一句 `/D=C:\` 就能绕过上面所有检查。
  IfSilent 0 +2
    Call ValidateInstallDir
FunctionEnd

; 正在跑的话先请它退出:exe 被占用时 `RMDir /r` 删不动它,装完会留下一半新一半
; 旧的目录,比直接失败还难查。**不替用户杀进程** —— 那是他的播放,让他自己关;
; 这里的「重试」就是再查一遍。
;
; 判据是**给 exe 开个写句柄**:进程映像被映射着的时候,Windows 不允许别人以写
; 方式打开它,会直接返回共享冲突。这个方法不看语言 —— 拿 tasklist 的输出文本去
; 匹配进程名,在中文 Windows 上得连「没有运行的任务」那句译文一起认,而那种字符串
; 一变(系统更新、换语言)就悄悄失效,变成「以为没在跑」。
Function EnsureNotRunning
  Push $0
  Push $1
  StrCpy $0 0
  loop:
    IfFileExists "$INSTDIR\${APP_EXE}" 0 done
    ClearErrors
    FileOpen $1 "$INSTDIR\${APP_EXE}" "a"
    IfErrors 0 opened
      ; 打不开 = 被占着 = 正在跑。
      IntOp $0 $0 + 1
      ; 静默安装没有人能点那个「重试」,弹框就是卡住 —— 直接带非零退出码失败。
      IfSilent silent_busy
      ${If} $0 > 5
        MessageBox MB_OK|MB_ICONSTOP "${APP_NAME} 还在运行,装不进去。$\r$\n$\r$\n请先关掉它,再重跑这个安装程序。"
        Abort
      ${EndIf}
      MessageBox MB_RETRYCANCEL|MB_ICONEXCLAMATION "${APP_NAME} 正在运行。$\r$\n$\r$\n请先关掉它,然后点「重试」。" IDRETRY loop
      Abort
      silent_busy:
      SetErrorLevel 5
      Abort
    opened:
      FileClose $1
  done:
  Pop $1
  Pop $0
FunctionEnd

Section "Nordic 主程序(必需)" SEC_APP
  SectionIn RO

  Call EnsureNotRunning

  ; 覆盖安装:旧版本的文件先清掉(目录该不该清,上面 ValidateInstallDir 已经判过)。
  ; `$INSTDIR` 是应用自己的目录,里面不会有用户的东西 —— 配置在 `%APPDATA%` 下,
  ; 这一条不碰它。
  RMDir /r "$INSTDIR"

  SetOutPath "$INSTDIR"
  File /r "${APPDIR}\*.*"

  WriteUninstaller "$INSTDIR\uninstall.exe"

  ; 「添加或删除程序」认的是这一段。**版本写在这里**,所以升级装完之后面板里
  ; 显示的是新版本,而不是上一次装的那个。
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" \
    "DisplayName" "${APP_NAME}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" \
    "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" \
    "Publisher" "${APP_PUBLISHER}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" \
    "DisplayIcon" "$INSTDIR\${APP_EXE}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" \
    "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" \
    "QuietUninstallString" '"$INSTDIR\uninstall.exe" /S'
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" \
    "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" \
    "URLInfoAbout" "${APP_URL}"
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" \
    "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" \
    "NoRepair" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" \
    "EstimatedSize" "${APP_SIZE_KB}"

  ; 卸载时要用,存在自己的键里。
  WriteRegStr HKCU "Software\${APP_ID}" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "Software\${APP_ID}" "Version" "${VERSION}"

  SetShellVarContext current
  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  CreateShortCut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}"
  CreateShortCut "$SMPROGRAMS\${APP_NAME}\卸载 ${APP_NAME}.lnk" "$INSTDIR\uninstall.exe"
SectionEnd

Section "桌面快捷方式" SEC_DESKTOP
  SetShellVarContext current
  CreateShortCut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}"
SectionEnd

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC_APP} "Nordic 主程序与运行库,必须装。"
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC_DESKTOP} "在桌面上放一个 Nordic 的图标;不想要就取消勾选。"
!insertmacro MUI_FUNCTION_DESCRIPTION_END

Section "Uninstall"
  SetShellVarContext current

  ; 正在跑的话先请它退出 —— 否则 exe 被占用,删一半就留下一个打不开的目录。
  ; 卸载时不等用户操作(他已经点了卸载),直接杀。
  ExecWait '"$SYSDIR\taskkill.exe" /IM ${APP_EXE} /F /T' $0

  Delete "$DESKTOP\${APP_NAME}.lnk"
  RMDir /r "$SMPROGRAMS\${APP_NAME}"
  RMDir /r "$INSTDIR"

  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}"
  DeleteRegKey HKCU "Software\${APP_ID}"

  ; 用户的设置在 `%APPDATA%` 下(歌单缓存、服务器地址、动效开关等),**故意不删**
  ; —— 卸载一个播放器不该顺手把「听过的歌」清掉。想彻底干净,自己在资源管理器
  ; 里删那个目录。
SectionEnd
