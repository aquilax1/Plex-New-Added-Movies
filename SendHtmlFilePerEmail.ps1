Param ([String]$EmailFrom,[String]$EmailTo,[String]$Subject,[String]$FileName,[String]$SmtpServer,[String]$UserName,[String]$Password)
if (test-path $FileName)
{
	$Body=Get-Content $FileName
	$SMTPClient = New-Object Net.Mail.SmtpClient($SmtpServer, 587) 
	$SMTPClient.EnableSsl = $True 
	$SMTPClient.Credentials = New-Object System.Net.NetworkCredential($UserName, $Password)
	$MailMessage = New-Object Net.Mail.MailMessage($EmailFrom, $EmailTo, $Subject, $Body)
	$MailMessage.IsBodyHtml = $True
	$SMTPClient.Send($MailMessage)
}