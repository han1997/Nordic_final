; 安装目录的两道闸 —— 从 `windows_installer.nsi` 里拆出来单独放,原因是**它得能单独
; 被验**:一个只在安装器内部调用的函数,想验就只能真去装一遍,而装的那一遍又会被
; `/D=` 的解析规则挡在前面 —— 实测 NSIS 对 `/D=X:\`、`/D=X:` 这两种写法**一声不响地
; 忽略**(退回默认目录,退出码还是 0),所以「用 /D= 指一个盘符根试试」根本试不到
; 这段代码。拆成 include 之后,测试脚本可以自己摆好 `$INSTDIR` 再调同一个函数,
; 验的是真身,不是抄来的副本。
;
; 依赖调用方先定义:`APP_NAME`、`APP_EXE`。
;
; 两道闸:
;
; 闸一:**目录不能就是盘符根**。`RMDir /r "$INSTDIR"` 是这一整轮唯一一处会删东西
; 的地方;如果 `$INSTDIR` 就是 `D:\`,这一句删的是整块盘。
;
; 判据不是「路径够不够深」,而是「它是不是根」—— 深度一层(`D:\Nordic`)是完全正常
; 的选择,要命的是根与非根那一线,别把前者一起拒了。两个信号,两个都得认(都实测过):
;   · `${GetParent} "$INSTDIR"` 为空 —— 盖住 `X:\`(NSIS 的 GetParent 对盘符根
;     返回的是空串,不是根自己);
;   · `$INSTDIR` 等于 `${GetRoot}`、或等于「根 + 反斜杠」(`GetRoot` 回 `C:`,不带
;     反斜杠)—— 盖住 `X:`、`X:\` 这两种写法。
;
; 闸二:**已存在的目录得是我们自己的**。它凭什么被清掉?凭目录里躺着
; `uninstall.exe` 或 `nordic.exe` 或 `flutter_windows.dll` —— 这三个只有我们的
; 安装包写得出来。一个既非空、又没有任何一个的目录(用户手滑点到「文档」),拒绝,
; 让他另选一个。**先看再删**,不是「反正清掉再装」。
; 目录不存在(全新的机器)或存在但是空的,当然放行。
;
; 拒绝时**静默装不弹框**:没人能点那个「确定」,弹出来就是卡住不动,调用方只看到
; 一个永远不返回的进程。静默走 SetErrorLevel + Abort(退出码 3 / 4,非 0 看得见)。
Function ValidateInstallDir
  Push $0
  Push $1

  ${If} $INSTDIR == ""
    MessageBox MB_OK|MB_ICONSTOP "请填一个安装目录。"
    Abort
  ${EndIf}

  ${GetRoot} "$INSTDIR" $0
  ${GetParent} "$INSTDIR" $1

  ${If} $1 == ""
    Goto bad_root
  ${EndIf}
  ${If} $INSTDIR == $0
    Goto bad_root
  ${EndIf}
  ${If} $INSTDIR == "$0\"
    Goto bad_root
  ${EndIf}
  Goto after_root

  bad_root:
    IfSilent 0 +3
      SetErrorLevel 3
      Abort
    MessageBox MB_OK|MB_ICONSTOP "'$INSTDIR' 就是盘符根,不能装在这里。$\r$\n$\r$\n请选一个目录,例如默认的 $LOCALAPPDATA\Programs\${APP_NAME}。"
    Abort

  after_root:
  ${DirState} "$INSTDIR" $0
  ${If} $0 == 1
    ; 存在且有东西 —— 只有在认得出来是我们的安装目录时才清。
    IfFileExists "$INSTDIR\uninstall.exe" ok
    IfFileExists "$INSTDIR\${APP_EXE}" ok
    IfFileExists "$INSTDIR\flutter_windows.dll" ok
      IfSilent 0 +3
        SetErrorLevel 4
        Abort
      MessageBox MB_OK|MB_ICONSTOP "'$INSTDIR' 里已经装着别的东西,不是 Nordic 的安装目录。$\r$\n$\r$\n装在这里会把它删掉,所以先停下来 —— 请换一个目录。"
      Abort
    ok:
  ${EndIf}

  Pop $1
  Pop $0
FunctionEnd
