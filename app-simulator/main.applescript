-- アプリ画面確認 v10
-- GitHub上のExpoアプリをすばやく見つけ、iPhone / Androidで確認します。

property appVersion : "v10"
property githubOwner : "gakkii415"
property supportRoot : (POSIX path of (path to home folder)) & "Library/Application Support/アプリ画面確認"
property appsRoot : supportRoot & "/アプリ"
property cacheFile : supportRoot & "/apps-cache.tsv"
property stateFile : supportRoot & "/state.tsv"
property keychainService : "アプリ画面確認-GitHub"
property keychainAccount : "github-token"
property launchLog : "/tmp/app-screen-check.log"

on run
	display notification "起動しています" with title "アプリ画面確認"
	my ensureFolder(supportRoot)
	my ensureFolder(appsRoot)
	
	set githubToken to my getGitHubToken()
	if githubToken is "" then return
	
	display notification "GitHubからアプリ一覧を更新しています" with title "アプリ画面確認"
	set searchResult to my findExpoApplications(githubToken)
	set searchSucceeded to item 1 of searchResult
	set appRecords to item 2 of searchResult
	
	if searchSucceeded and (count of appRecords) > 0 then
		my writeAppCache(appRecords)
	else if (count of appRecords) is 0 then
		set appRecords to my readAppCache()
		if (count of appRecords) > 0 then
			display notification "GitHubに接続できないため前回の一覧を使います" with title "アプリ画面確認"
		end if
	end if
	
	if (count of appRecords) is 0 then
		display alert "アプリが見つかりません" message "GitHub上にExpoアプリが見つかりませんでした。" & return & return & "対象は package.json に Expo が含まれるアプリです。"
		return
	end if
	
	set savedState to my readState()
	set lastLabel to item 1 of savedState
	set lastDevice to item 2 of savedState
	set appRecords to my prioritizeLastUsed(appRecords, lastLabel)
	
	set appLabels to {}
	repeat with appRecord in appRecords
		set end of appLabels to item 1 of appRecord
	end repeat
	
	if lastLabel is not "" and my listContains(appLabels, lastLabel) then
		set selectedApp to choose from list appLabels with title "アプリ画面確認" with prompt "確認するアプリを選んでください" default items {lastLabel} OK button name "次へ" cancel button name "キャンセル"
	else
		set selectedApp to choose from list appLabels with title "アプリ画面確認" with prompt "確認するアプリを選んでください" OK button name "次へ" cancel button name "キャンセル"
	end if
	if selectedApp is false then return
	
	set selectedLabel to item 1 of selectedApp
	set selectedRecord to my recordForLabel(appRecords, selectedLabel)
	set repoName to item 2 of selectedRecord
	set repoFullName to item 3 of selectedRecord
	set expoSubPath to item 4 of selectedRecord
	
	set deviceLabels to {"iPhoneで開く", "Androidで開く"}
	if lastDevice is "Android" then
		set deviceChoice to choose from list deviceLabels with title "アプリ画面確認" with prompt "確認する端末を選んでください" default items {"Androidで開く"} OK button name "開く" cancel button name "キャンセル"
	else
		set deviceChoice to choose from list deviceLabels with title "アプリ画面確認" with prompt "確認する端末を選んでください" default items {"iPhoneで開く"} OK button name "開く" cancel button name "キャンセル"
	end if
	if deviceChoice is false then return
	
	if item 1 of deviceChoice is "Androidで開く" then
		set deviceName to "Android"
	else
		set deviceName to "iPhone"
	end if
	
	my writeState(selectedLabel, deviceName)
	
	set repoPath to appsRoot & "/" & repoName
	display notification "最新版を準備しています" with title "アプリ画面確認"
	if my prepareRepository(repoFullName, repoPath, githubToken) is false then return
	
	if expoSubPath is "" then
		set expoPath to repoPath
	else
		set expoPath to repoPath & "/" & expoSubPath
	end if
	
	my launchExpo(expoPath, deviceName, selectedLabel)
end run

on getGitHubToken()
	try
		set savedToken to do shell script "security find-generic-password -s " & quoted form of keychainService & " -a " & quoted form of keychainAccount & " -w"
		if savedToken is not "" then return savedToken
	end try
	
	set tokenDialog to display dialog "GitHubの読み取り用トークンを入力してください。" & return & return & "初回だけ必要です。Macのキーチェーンに保存します。" default answer "" with title "アプリ画面確認" buttons {"キャンセル", "保存"} default button "保存" with hidden answer
	if button returned of tokenDialog is not "保存" then return ""
	set githubToken to text returned of tokenDialog
	if githubToken is "" then return ""
	
	if my tokenWorks(githubToken) is false then
		display alert "GitHubに接続できませんでした" message "トークンが正しいか、Repository access と Contents: Read-only を確認してください。"
		return ""
	end if
	
	try
		do shell script "security add-generic-password -U -s " & quoted form of keychainService & " -a " & quoted form of keychainAccount & " -w " & quoted form of githubToken
		return githubToken
	on error errorMessage
		display alert "トークンを保存できませんでした" message errorMessage
		return ""
	end try
end getGitHubToken

on tokenWorks(githubToken)
	try
		set resultText to do shell script my apiCommand(githubToken, "https://api.github.com/user", "application/vnd.github+json")
		return resultText contains "\"login\""
	on error
		return false
	end try
end tokenWorks

on findExpoApplications(githubToken)
	set searchUrl to "https://api.github.com/search/code?q=%22expo%22+filename%3Apackage.json+user%3A" & githubOwner & "&per_page=100"
	try
		set searchJson to do shell script my apiCommand(githubToken, searchUrl, "application/vnd.github+json")
	on error
		return {false, {}}
	end try
	
	set jsCode to "ObjC.import('stdlib'); const s=JSON.parse($.getenv('SEARCH_JSON')); (s.items||[]).map(x=>[x.repository.name,x.repository.full_name,x.path].join('\\t')).join('\\n')"
	try
		set matchText to do shell script "SEARCH_JSON=" & quoted form of searchJson & " /usr/bin/osascript -l JavaScript -e " & quoted form of jsCode
	on error
		return {false, {}}
	end try
	
	if matchText is "" then return {true, {}}
	
	set results to {}
	set seenKeys to {}
	repeat with matchLine in paragraphs of matchText
		set oldTID to AppleScript's text item delimiters
		set AppleScript's text item delimiters to tab
		set parts to text items of matchLine
		set AppleScript's text item delimiters to oldTID
		
		if (count of parts) >= 3 then
			set repoName to item 1 of parts
			set repoFullName to item 2 of parts
			set packagePath to item 3 of parts
			set uniqueKey to repoFullName & ":" & packagePath
			
			if my listContains(seenKeys, uniqueKey) is false then
				set end of seenKeys to uniqueKey
				set packageJson to my fetchPackageJson(githubToken, repoFullName, packagePath)
				if packageJson is not "" then
					set appName to my expoPackageName(packageJson)
					if appName is not false then
						set subPath to my parentPath(packagePath)
						if subPath is "" then
							set appLabel to repoName
						else
							set appLabel to repoName & " / " & appName
						end if
						set end of results to {appLabel, repoName, repoFullName, subPath}
					end if
				end if
			end if
		end if
	end repeat
	
	return {true, results}
end findExpoApplications

on fetchPackageJson(githubToken, repoFullName, packagePath)
	set fileUrl to "https://api.github.com/repos/" & repoFullName & "/contents/" & packagePath
	try
		return do shell script my apiCommand(githubToken, fileUrl, "application/vnd.github.raw+json")
	on error
		return ""
	end try
end fetchPackageJson

on expoPackageName(packageJson)
	set jsCode to "ObjC.import('stdlib'); const p=JSON.parse($.getenv('PACKAGE_JSON')); const d=Object.assign({},p.dependencies||{},p.devDependencies||{}); d.expo ? (p.name||'Expo app') : ''"
	try
		set appName to do shell script "PACKAGE_JSON=" & quoted form of packageJson & " /usr/bin/osascript -l JavaScript -e " & quoted form of jsCode
		if appName is "" then return false
		return appName
	on error
		return false
	end try
end expoPackageName

on prepareRepository(repoFullName, repoPath, githubToken)
	set authValue to do shell script "printf %s " & quoted form of ("x-access-token:" & githubToken) & " | /usr/bin/base64"
	if my folderExists(repoPath) then
		set commandText to "cd " & quoted form of repoPath & " && git -c http.extraHeader=" & quoted form of ("Authorization: Basic " & authValue) & " pull --ff-only"
	else
		set commandText to "git -c http.extraHeader=" & quoted form of ("Authorization: Basic " & authValue) & " clone " & quoted form of ("https://github.com/" & repoFullName & ".git") & " " & quoted form of repoPath
	end if
	
	try
		do shell script "/bin/zsh -lc " & quoted form of commandText
		return true
	on error errorMessage
		display alert "最新版を準備できませんでした" message "GitHubから更新できませんでした。" & return & return & errorMessage
		return false
	end try
end prepareRepository

on launchExpo(appPath, deviceName, appLabel)
	if my folderExists(appPath) is false or my fileExists(appPath & "/package.json") is false then
		display alert "アプリの場所が見つかりません" message appPath
		return
	end if
	
	set nodePath to my findCommand("node")
	set npmPath to my findCommand("npm")
	if nodePath is "" or npmPath is "" then
		display alert "Node.jsが見つかりません" message "Node.js / npm の実行環境を確認できませんでした。"
		return
	end if
	
	set nodeBin to do shell script "/usr/bin/dirname " & quoted form of nodePath
	set homePath to POSIX path of (path to home folder)
	set sdkRoot to homePath & "Library/Android/sdk"
	set shellPath to nodeBin & ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" & sdkRoot & "/platform-tools:" & sdkRoot & "/emulator"
	set envPrefix to "export PATH=" & quoted form of shellPath & "; export ANDROID_HOME=" & quoted form of sdkRoot & "; "
	
	if my ensureDependencies(appPath, npmPath, envPrefix) is false then return
	
	if deviceName is "iPhone" then
		display notification "iPhone Simulatorを準備しています" with title "アプリ画面確認"
		try
			do shell script "/usr/bin/open -a Simulator"
		end try
		set platformOption to "--ios"
		set openingText to "Opening on iOS"
	else
		display notification "Android Emulatorを準備しています" with title "アプリ画面確認"
		if my ensureAndroidEmulator(sdkRoot) is false then return
		set platformOption to "--android"
		set openingText to "Opening on Android"
	end if
	
	set expoPath to appPath & "/node_modules/.bin/expo"
	if my fileExists(expoPath) is false then
		display alert "Expoが見つかりません" message "依存関係の準備後もExpoを確認できませんでした。"
		return
	end if
	
	set freePort to my findFreePort()
	do shell script "/bin/rm -f " & quoted form of launchLog
	set setupCommand to envPrefix & "cd " & quoted form of appPath & " && exec " & quoted form of expoPath & " start " & platformOption & " --port " & freePort
	
	try
		set expoPid to do shell script "nohup /bin/zsh -lc " & quoted form of setupCommand & " > " & quoted form of launchLog & " 2>&1 & echo $!"
	on error errorMessage
		display alert "Expoを起動できませんでした" message errorMessage
		return
	end try
	
	display notification appLabel & " を " & deviceName & " で開いています" with title "アプリ画面確認"
	
	repeat with attempt from 1 to 20
		delay 2
		if my logContains(openingText) then
			display notification "起動しました" with title "アプリ画面確認"
			return
		end if
		if my logHasFailure() then
			display alert "起動に失敗しました" message my launchFailureHelp(deviceName)
			return
		end if
		if my processIsRunning(expoPid) is false then
			display alert "起動処理が停止しました" message my launchFailureHelp(deviceName)
			return
		end if
		if attempt is 6 then display notification "まだ処理中です" with title "アプリ画面確認"
	end repeat
	
	if my processIsRunning(expoPid) then
		display notification "Expoは動作中です。端末への接続を続けています" with title "アプリ画面確認"
	else
		display alert "起動処理が停止しました" message my launchFailureHelp(deviceName)
	end if
end launchExpo

on ensureDependencies(appPath, npmPath, envPrefix)
	set hashFile to appPath & "/node_modules/.app-screen-package-hash"
	set currentHash to my packageHash(appPath)
	set savedHash to ""
	if my fileExists(hashFile) then
		try
			set savedHash to do shell script "/bin/cat " & quoted form of hashFile
		end try
	end if
	
	if my folderExists(appPath & "/node_modules") and currentHash is not "" and currentHash is savedHash then return true
	
	display notification "アプリの必要ファイルを更新しています" with title "アプリ画面確認"
	try
		do shell script "/bin/zsh -lc " & quoted form of (envPrefix & "cd " & quoted form of appPath & " && " & quoted form of npmPath & " install --no-audit --no-fund")
	on error errorMessage
		display alert "アプリの準備に失敗しました" message errorMessage
		return false
	end try
	
	set newHash to my packageHash(appPath)
	if newHash is not "" then
		try
			do shell script "mkdir -p " & quoted form of (appPath & "/node_modules") & " && printf %s " & quoted form of newHash & " > " & quoted form of hashFile
		end try
	end if
	return true
end ensureDependencies

on packageHash(appPath)
	try
		set commandText to "cd " & quoted form of appPath & " && { /usr/bin/shasum package.json; [ ! -f package-lock.json ] || /usr/bin/shasum package-lock.json; } | /usr/bin/shasum | /usr/bin/awk '{print $1}'"
		return do shell script "/bin/zsh -lc " & quoted form of commandText
	on error
		return ""
	end try
end packageHash

on ensureAndroidEmulator(sdkRoot)
	set adbPath to sdkRoot & "/platform-tools/adb"
	set emulatorPath to sdkRoot & "/emulator/emulator"
	if my fileExists(adbPath) is false or my fileExists(emulatorPath) is false then
		display alert "Android Emulatorが見つかりません" message "Android StudioのDevice Managerで仮想端末を作成してください。"
		return false
	end if
	
	try
		do shell script quoted form of adbPath & " start-server >/dev/null 2>&1"
	end try
	
	set deviceId to my onlineAndroidEmulator(adbPath)
	if deviceId is "" then
		set anyEmulator to my anyAndroidEmulator(adbPath)
		if anyEmulator is "" then
			try
				set avdName to do shell script quoted form of emulatorPath & " -list-avds | /usr/bin/head -n 1"
				if avdName is "" then
					display alert "Android端末がありません" message "Android StudioのDevice Managerで仮想端末を1台作成してください。"
					return false
				end if
				do shell script "nohup " & quoted form of emulatorPath & " -avd " & quoted form of avdName & " > /tmp/app-screen-check-android.log 2>&1 &"
			on error errorMessage
				display alert "Android Emulatorを起動できませんでした" message errorMessage
				return false
			end try
		end if
	end if
	
	repeat with i from 1 to 60
		delay 2
		set deviceId to my onlineAndroidEmulator(adbPath)
		if deviceId is not "" then
			try
				set booted to do shell script quoted form of adbPath & " -s " & quoted form of deviceId & " shell getprop sys.boot_completed 2>/dev/null"
				if booted is "1" then
					try
						do shell script quoted form of adbPath & " -s " & quoted form of deviceId & " shell input keyevent 82 >/dev/null 2>&1"
					end try
					return true
				end if
			end try
		end if
		
		if i is 8 then display notification "Androidを起動中です" with title "アプリ画面確認"
		if i is 20 then display notification "Androidのホーム画面を準備しています" with title "アプリ画面確認"
		if i is 40 then display notification "Androidの起動完了を待っています" with title "アプリ画面確認"
	end repeat
	
	display alert "Androidの起動に時間がかかっています" message "Emulatorのホーム画面が表示されたら、もう一度Androidを選んでください。"
	return false
end ensureAndroidEmulator

on onlineAndroidEmulator(adbPath)
	try
		return do shell script quoted form of adbPath & " devices | /usr/bin/awk '$1 ~ /^emulator-/ && $2 == \"device\" {print $1; exit}'"
	on error
		return ""
	end try
end onlineAndroidEmulator

on anyAndroidEmulator(adbPath)
	try
		return do shell script quoted form of adbPath & " devices | /usr/bin/awk '$1 ~ /^emulator-/ {print $1; exit}'"
	on error
		return ""
	end try
end anyAndroidEmulator

on launchFailureHelp(deviceName)
	set logText to my lastLogLines()
	if deviceName is "Android" then
		return "Android Emulatorとの接続に失敗しました。" & return & return & "Androidのホーム画面が表示されているか確認してください。" & return & return & "直近のログ:" & return & logText
	else
		return "iPhone Simulatorとの接続に失敗しました。" & return & return & "直近のログ:" & return & logText
	end if
end launchFailureHelp

on processIsRunning(processId)
	try
		do shell script "/bin/kill -0 " & processId
		return true
	on error
		return false
	end try
end processIsRunning

on logContains(searchText)
	try
		do shell script "/usr/bin/grep -Fq " & quoted form of searchText & " " & quoted form of launchLog
		return true
	on error
		return false
	end try
end logContains

on logHasFailure()
	try
		do shell script "/usr/bin/grep -Eiq 'CommandError:|npm ERR!|EADDRINUSE|No Android connected device|No development build|xcrun: error|Unable to resolve' " & quoted form of launchLog
		return true
	on error
		return false
	end try
end logHasFailure

on lastLogLines()
	try
		set logText to do shell script "/usr/bin/tail -n 10 " & quoted form of launchLog
		if logText is "" then return "ログはまだありません。"
		return logText
	on error
		return "ログを取得できませんでした。"
	end try
end lastLogLines

on findCommand(commandName)
	try
		set resultPath to do shell script "/bin/zsh -lic " & quoted form of ("command -v " & commandName & " 2>/dev/null")
		if resultPath contains return then set resultPath to paragraph -1 of resultPath
		return resultPath
	on error
		return ""
	end try
end findCommand

on findFreePort()
	try
		set foundPort to do shell script "/bin/zsh -lc " & quoted form of "for p in {8081..8090}; do if ! /usr/sbin/lsof -iTCP:$p -sTCP:LISTEN -t >/dev/null 2>&1; then echo $p; break; fi; done"
		if foundPort is not "" then return foundPort
	end try
	return "8081"
end findFreePort

on writeAppCache(appRecords)
	try
		set cacheText to ""
		repeat with appRecord in appRecords
			set cacheText to cacheText & item 1 of appRecord & tab & item 2 of appRecord & tab & item 3 of appRecord & tab & item 4 of appRecord & linefeed
		end repeat
		do shell script "printf %s " & quoted form of cacheText & " > " & quoted form of cacheFile
	end try
end writeAppCache

on readAppCache()
	if my fileExists(cacheFile) is false then return {}
	try
		set cacheText to do shell script "/bin/cat " & quoted form of cacheFile
	on error
		return {}
	end try
	if cacheText is "" then return {}
	
	set results to {}
	repeat with cacheLine in paragraphs of cacheText
		if cacheLine is not "" then
			set oldTID to AppleScript's text item delimiters
			set AppleScript's text item delimiters to tab
			set parts to text items of cacheLine
			set AppleScript's text item delimiters to oldTID
			if (count of parts) >= 4 then set end of results to {item 1 of parts, item 2 of parts, item 3 of parts, item 4 of parts}
		end if
	end repeat
	return results
end readAppCache

on writeState(appLabel, deviceName)
	try
		set stateText to appLabel & tab & deviceName
		do shell script "printf %s " & quoted form of stateText & " > " & quoted form of stateFile
	end try
end writeState

on readState()
	if my fileExists(stateFile) is false then return {"", "iPhone"}
	try
		set stateText to do shell script "/bin/cat " & quoted form of stateFile
		set oldTID to AppleScript's text item delimiters
		set AppleScript's text item delimiters to tab
		set parts to text items of stateText
		set AppleScript's text item delimiters to oldTID
		if (count of parts) >= 2 then return {item 1 of parts, item 2 of parts}
	end try
	return {"", "iPhone"}
end readState

on prioritizeLastUsed(appRecords, lastLabel)
	if lastLabel is "" then return appRecords
	set prioritized to {}
	set restRecords to {}
	repeat with appRecord in appRecords
		if item 1 of appRecord is lastLabel then
			set end of prioritized to appRecord
		else
			set end of restRecords to appRecord
		end if
	end repeat
	return prioritized & restRecords
end prioritizeLastUsed

on recordForLabel(appRecords, targetLabel)
	repeat with appRecord in appRecords
		if item 1 of appRecord is targetLabel then return appRecord
	end repeat
	return item 1 of appRecords
end recordForLabel

on listContains(sourceList, targetValue)
	repeat with sourceItem in sourceList
		if sourceItem as text is targetValue as text then return true
	end repeat
	return false
end listContains

on parentPath(filePath)
	if filePath does not contain "/" then return ""
	set oldTID to AppleScript's text item delimiters
	set AppleScript's text item delimiters to "/"
	set parts to text items of filePath
	set AppleScript's text item delimiters to oldTID
	if (count of parts) <= 1 then return ""
	set parentParts to items 1 thru -2 of parts
	set AppleScript's text item delimiters to "/"
	set resultPath to parentParts as text
	set AppleScript's text item delimiters to oldTID
	return resultPath
end parentPath

on apiCommand(githubToken, apiUrl, acceptHeader)
	return "/usr/bin/curl -sS --fail -H " & quoted form of ("Authorization: Bearer " & githubToken) & " -H " & quoted form of ("Accept: " & acceptHeader) & " -H " & quoted form of "X-GitHub-Api-Version: 2022-11-28" & " " & quoted form of apiUrl
end apiCommand

on folderExists(folderPath)
	try
		do shell script "test -d " & quoted form of folderPath
		return true
	on error
		return false
	end try
end folderExists

on fileExists(filePath)
	try
		do shell script "test -f " & quoted form of filePath
		return true
	on error
		return false
	end try
end fileExists

on ensureFolder(folderPath)
	do shell script "mkdir -p " & quoted form of folderPath
end ensureFolder
