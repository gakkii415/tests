-- アプリ画面確認 固定ランチャー v2
-- 起動時にGitHub上の最新版を取得して実行します。
-- 取得失敗時は前回正常に取得した版を使います。

property rawUrl : "https://raw.githubusercontent.com/gakkii415/tests/main/app-simulator/main.applescript"
property apiUrl : "https://api.github.com/repos/gakkii415/tests/contents/app-simulator/main.applescript?ref=main"
property keychainService : "アプリ画面確認-GitHub"
property keychainAccount : "github-token"

on run
	set supportFolder to (POSIX path of (path to home folder)) & "Library/Application Support/アプリ画面確認"
	set cachedScript to supportFolder & "/main.applescript"
	set temporaryScript to supportFolder & "/main.applescript.download"
	set compileCheck to supportFolder & "/main-check.scpt"
	
	do shell script "mkdir -p " & quoted form of supportFolder
	
	set updatedSuccessfully to false
	
	-- 1. まず公開Raw URLから取得
	try
		do shell script "/usr/bin/curl -fsSL " & quoted form of rawUrl & " -o " & quoted form of temporaryScript
		if my scriptIsValid(temporaryScript, compileCheck) then
			do shell script "/bin/mv -f " & quoted form of temporaryScript & " " & quoted form of cachedScript
			set updatedSuccessfully to true
		end if
	end try
	
	-- 2. Raw取得に失敗した場合は、保存済みGitHubトークンでAPI取得
	if updatedSuccessfully is false then
		try
			set githubToken to do shell script "security find-generic-password -s " & quoted form of keychainService & " -a " & quoted form of keychainAccount & " -w"
			
			if githubToken is not "" then
				set downloadCommand to "/usr/bin/curl -fsSL -H " & quoted form of ("Authorization: Bearer " & githubToken) & " -H " & quoted form of "Accept: application/vnd.github.raw+json" & " -H " & quoted form of "X-GitHub-Api-Version: 2022-11-28" & " " & quoted form of apiUrl & " -o " & quoted form of temporaryScript
				
				do shell script downloadCommand
				
				if my scriptIsValid(temporaryScript, compileCheck) then
					do shell script "/bin/mv -f " & quoted form of temporaryScript & " " & quoted form of cachedScript
					set updatedSuccessfully to true
				end if
			end if
		end try
	end if
	
	try
		do shell script "/bin/rm -f " & quoted form of temporaryScript & " " & quoted form of compileCheck
	end try
	
	if updatedSuccessfully is false then
		if my fileExists(cachedScript) is false then
			display alert "最新版を取得できませんでした" message "GitHubから本体を取得できず、前回版もまだ保存されていません。"
			return
		end if
		
		display notification "前回正常に取得した版を使用します" with title "アプリ画面確認"
	end if
	
	try
		do shell script "/usr/bin/osascript " & quoted form of cachedScript
	on error errorMessage
		display alert "アプリ画面確認を起動できませんでした" message errorMessage
	end try
end run

on scriptIsValid(scriptPath, compilePath)
	try
		do shell script "/usr/bin/osacompile -o " & quoted form of compilePath & " " & quoted form of scriptPath
		do shell script "/bin/rm -f " & quoted form of compilePath
		return true
	on error
		try
			do shell script "/bin/rm -f " & quoted form of compilePath
		end try
		return false
	end try
end scriptIsValid

on fileExists(filePath)
	try
		do shell script "test -f " & quoted form of filePath
		return true
	on error
		return false
	end try
end fileExists
