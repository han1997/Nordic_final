; 安装目录两道闸的自测 —— **编译成 exe、真跑一遍**,不在源码上做文本匹配。
;
; 为什么非要这样测:
;   1. `/D=` 表达不出危险路径。实测(makensis 3.13)`setup.exe /S /D=X:\` 与
;      `/S /D=X:` 都被 NSIS **一声不响地忽略** —— `$INSTDIR` 退回默认值,退出码还是
;      0。拿安装包加 `/D=` 指一个盘符根去试,根本走不到守闸那两行,那种测法会一路
;      绿着放行。
;   2. 闸里用的是 `Abort`,而 `Abort` 会**结束整个安装进程** —— 一个进程只能测一条
;      用例。所以这里分两层:外层进程摆用例表、逐个 ExecWait 子进程;子进程读自己
;      那条路径、调同一个函数、按退出码终止。
;
; 被测的是**真身**:`windows_installer_guard.nsh`,与安装包里是同一份文件。
;
; 退出码:外层 0 = 全部通过,非 0 = 失败条数。每条的实测值写进 `guard_test.log`。
; 跑法见 tool/build.sh 的 windows 支路;也可单独:
;   makensis -INPUTCHARSET UTF8 tool/windows_installer_guard_test.nsi && ./guard_test.exe

Unicode true

!include "LogicLib.nsh"
!include "FileFunc.nsh"

!define APP_NAME "Nordic"
!define APP_EXE "nordic.exe"

!include "windows_installer_guard.nsh"

!ifndef GUARD_TEST_OUTFILE
  !define GUARD_TEST_OUTFILE "guard_test.exe"
!endif

Name "Nordic 安装目录守闸自测"
OutFile "${GUARD_TEST_OUTFILE}"
InstallDir "$EXEDIR\sandbox"
RequestExecutionLevel user
SilentInstall silent

!define CASES "$EXEDIR\cases"
!define CASE_COUNT 10

Var caseId
Var failed
Var idx
Var actual
Var expect

; 写一条用例:$R1 = 序号,$R2 = 目录,$R3 = 期望退出码。
Function WriteCase
  FileOpen $9 "${CASES}\$R1.path" w
  FileWrite $9 "$R2"
  FileClose $9
  FileOpen $9 "${CASES}\$R1.expect" w
  FileWrite $9 "$R3"
  FileClose $9
FunctionEnd

; 外层:摆场地、写用例表、逐个子进程跑、比对。
Function OuterDriver
  RMDir /r "${CASES}"
  CreateDirectory "${CASES}"
  ; 干净起点:这里只造测试用的目录,别的不碰。
  CreateDirectory "$EXEDIR\boot"      ; 空目录 -> 放行
  CreateDirectory "$EXEDIR\foreign"   ; 有别人的文件 -> 拒
  FileOpen $9 "$EXEDIR\foreign\我的文档.txt" w
  FileWrite $9 "user data"
  FileClose $9
  CreateDirectory "$EXEDIR\ours"      ; 有我们的标记文件 -> 放行
  FileOpen $9 "$EXEDIR\ours\flutter_windows.dll" w
  FileWrite $9 "x"
  FileClose $9
  CreateDirectory "$EXEDIR\ours2"
  FileOpen $9 "$EXEDIR\ours2\uninstall.exe" w
  FileWrite $9 "x"
  FileClose $9

  ; ---- 闸一:盘符根的各种写法,全都要拒(3)。----
  ; 4 种写法都要认:`C:\` 靠 GetParent 为空;`C:` 靠与 GetRoot 相等;
  ; `C:/` 靠与「根 + 正斜杠」相等 —— 只认一种写法的话,另一种就漏过去了。
  StrCpy $R1 1
  StrCpy $R2 "C:\"
  StrCpy $R3 3
  Call WriteCase
  StrCpy $R1 2
  StrCpy $R2 "C:"
  StrCpy $R3 3
  Call WriteCase
  StrCpy $R1 3
  StrCpy $R2 "c:/"
  StrCpy $R3 3
  Call WriteCase
  ; 不存在的盘符也要拒 —— 守闸是比字符串,不看那块盘在不在(少依赖外部状态)。
  StrCpy $R1 4
  StrCpy $R2 "Z:\"
  StrCpy $R3 3
  Call WriteCase

  ; ---- 放行(0):别把正常选择一起拒了。----
  StrCpy $R1 5
  StrCpy $R2 "$EXEDIR\sandbox\Nordic"   ; 不存在
  StrCpy $R3 0
  Call WriteCase
  StrCpy $R1 6
  StrCpy $R2 "$EXEDIR\boot"             ; 存在但空
  StrCpy $R3 0
  Call WriteCase
  StrCpy $R1 7
  StrCpy $R2 "$EXEDIR\ours"             ; 认得出是我们的(覆盖安装)
  StrCpy $R3 0
  Call WriteCase
  StrCpy $R1 8
  StrCpy $R2 "$EXEDIR\ours2"            ; 只有 uninstall.exe 也算认出
  StrCpy $R3 0
  Call WriteCase

  ; ---- 闸二:拒(4)既有目录里不是我们的东西。----
  StrCpy $R1 9
  StrCpy $R2 "$EXEDIR\foreign"
  StrCpy $R3 4
  Call WriteCase
  ; 相对路径也得当绝对路径判,不能因为「看着不像绝对路径」就漏
  StrCpy $R1 10
  StrCpy $R2 "C:\NordicGuardTestOneLevel"
  StrCpy $R3 0
  Call WriteCase

  ; ---- 逐个跑 ----
  StrCpy $failed 0
  StrCpy $idx 0
  FileOpen $8 "$EXEDIR\guard_test.log" w
  FileWrite $8 "序号 | 目录 | 期望 | 实测$\r$\n"
  loop:
    IntOp $idx $idx + 1
    ${If} $idx > ${CASE_COUNT}
      Goto finished
    ${EndIf}
    FileOpen $9 "${CASES}\$idx.expect" r
    FileRead $9 $expect
    FileClose $9
    FileOpen $9 "${CASES}\$idx.path" r
    FileRead $9 $R2
    FileClose $9
    ClearErrors
    ExecWait '"$EXEDIR\guard_test.exe" /CASE=$idx' $actual
    ${If} $actual != $expect
      IntOp $failed $failed + 1
      FileWrite $8 "$idx | $R2 | $expect | $actual  <-- 不一致$\r$\n"
    ${Else}
      FileWrite $8 "$idx | $R2 | $expect | $actual$\r$\n"
    ${EndIf}
    Goto loop
  finished:
    FileWrite $8 "失败 $failed 条$\r$\n"
  FileClose $8
FunctionEnd

Function .onInit
  ${GetOptions} $CMDLINE "/CASE=" $caseId
  ${If} $caseId == ""
    Call OuterDriver
    ; 失败条数当退出码 —— build.sh 只看这一个数字。
    SetErrorLevel $failed
    Quit
  ${EndIf}

  ; 子进程:读自己那条用例的目录,摆进 $INSTDIR,调真身。
  ; **从 .onInit 里调**,与安装包生产路径一致(静默安装只有这一处会跑)。
  FileOpen $9 "${CASES}\$caseId.path" r
  FileRead $9 $INSTDIR
  FileClose $9
  Call ValidateInstallDir
  ; 走到这儿说明守闸放行了。退出码必须**显式**写成 0:实测裸 `Quit` 的退出码是 2
  ; (与 `Abort` 同值),不写这一句,所有「该放行」的用例都会被读成拒绝。
  SetErrorLevel 0
  Quit
FunctionEnd

Section
SectionEnd
