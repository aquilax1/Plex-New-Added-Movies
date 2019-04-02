<#
.SYNOPSIS
Powershell script to generate an HTML report of the last added movies to PLEX

.DESCRIPTION
This powershell script scans PLEX for new added movies in the last X days and generates an HTML report, which can be for example sent per email.

.PARAMETER libraries
A list of PLEX libraries, which will be scanned for new movies, if omitted all the libraries will be scanned.

.PARAMETER plex
The URL of PLEX, if omitted it will be used the default URL http://localhost:32400, which is the URL of the local instance of PLEX

.PARAMETER days
The number of the days to consider for new movies, if omitted it will be used the default value of 7 days

.PARAMETER htmlTemplate
The name of the HTML template file to use to generate the HTML report, if omitted it will be used the default HTML template PlexNewAddedMoviesTemplate.html

.PARAMETER htmlOutput
The name of the HTML file to generate based on the HTML template, if omitted it will be used the default file name PlexNewAddedMovies.html

.PARAMETER token
Authentication token to access PLEX WEB API, required if the origin IP has not be added to the list of the allowed networks without authentication.
For more information about authentication token and allowed network without authentication follow those links:
https://support.plex.tv/hc/en-us/articles/200890058-Require-authentication-for-local-network-access
https://support.plex.tv/hc/en-us/articles/204059436-Finding-an-authentication-token-X-Plex-Token

.EXAMPLE
./PlexNewAddedMovies.ps1
It generates a HTLM report for the local instance of PLEX for all libraries and for the movies added in the last seven days

.EXAMPLE
./PlexNewAddedMovies.ps1 -libraries Series -days 3 -htmlOutput NewSeries.html
It generates the HTLM report NewSeries.html for the local instance of PLEX for the library Series and for the episodes added in the last three days

.LINK
https://github.com/aquilax1/Plex-New-Added-Movies
#>
param([String[]] $libraries, [String] $plex="http://localhost:32400", [Int] $days=7, [string] $htmlTemplate=".\PlexNewAddedMoviesTemplate.html", [string] $htmlOutput=".\PlexNewAddedMovies.html", [string] $token)
Add-Type -AssemblyName System.Drawing

Function Convert-FromUnixdate ($UnixDate) { if ($UnixDate -eq $Null) { $Null } else {(get-date "1/1/1970").AddSeconds($UnixDate) }}
Function Resize-Image ($bytes,$width) { $img=[System.Drawing.Image]::FromStream([System.IO.MemoryStream]$bytes); $scale=$width/$img.Width; $newImg = new-object System.Drawing.Bitmap([Int][math]::Floor($scale*$img.Width),[Int][math]::Floor($scale*$img.Height)); $g = [System.Drawing.Graphics]::FromImage($newImg); $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic; $g.DrawImage($img, 0, 0, $newImg.Width, $newImg.Height); $stream = new-object System.IO.MemoryStream; $newImg.Save($stream, [System.Drawing.Imaging.ImageFormat]::Jpeg); $stream.ToArray(); }

$web=New-Object System.Net.WebCLient
$doc=New-Object System.Xml.XmlDocument

#replace 127.0.0.1 and localhost with the machine ip because otherwiese plex returns a 401 access deneied
$plex=$plex -replace "localhost|127\.0\.0\.1", ((ipconfig | findstr [0-9].\.)[0]).Split()[-1]
#if the token is available, prepare it to be added at the end of each request
if (-not [String]::IsNullOrEmpty($token)) { $token="?X-Plex-Token="+$token }
#delete the output file if exists, just to avoid confusions
If (Test-Path $htmlOutput) { remove-item $htmlOutput }
#get server id and name, required to generate the links
$xml=[xml]$web.DownloadString($plex+$token);
$servername=$xml.MediaContainer.friendlyName
$serverid=$xml.MediaContainer.machineIdentifier;
#get all the library and filter them if $libraries is defined
$dirs=([xml]$web.DownloadString($plex+"/library/sections"+$token)).MediaContainer.Directory | where {$libraries -eq $Null -or $libraries -contains $_.title }
#get all  the movies of the libraries
$movies=$dirs | foreach{$xml=[xml]$web.DownloadString(($plex+"/library/sections/{0}/all"+$token) -F $_.key); $library=$xml.MediaContainer.librarySectionTitle; $xml.MediaContainer.Video | where {$_.type -eq "movie"} | select -p $library, title, year, tagline, summary, rating, thumb, @{Name="link"; Expression={$plex+"/web/index.html#!/server/"+$serverid+"/details/"+[System.Uri]::EscapeDataString($_.key)+$token}}, @{Name="duration"; Expression={Convert-FromUnixdate($_.duration/1000)}}, @{Name="addedAt"; Expression={Convert-FromUnixdate($_.addedAt)}}, @{Name="released"; Expression={[DateTime]::Parse($_.originallyAvailableAt)}}, @{Name="genre"; Expression={$arr=$_.Genre|foreach{$_.tag}; [System.String]::Join(", ",$arr); }}, @{Name="writer"; Expression={$arr=$_.Writer|foreach{$_.tag}; [System.String]::Join(", ",$arr); }}, @{Name="director"; Expression={$arr=$_.Director|foreach{$_.tag}; [System.String]::Join(", ",$arr); }}, @{Name="country"; Expression={$arr=$_.Country|foreach{$_.tag}; [System.String]::Join(", ",$arr); }}, @{Name="role"; Expression={$arr=$_.Role|foreach{$_.tag}; [System.String]::Join(", ",$arr); }} }
#get only the movies not older than x days
$from=(get-date).Date.AddDays(-$days);
$movies=$movies | where {$_.addedAt -gt $from}
if ($movies.Length -gt 0)
{
	Write-Host (get-date) "There are" $movies.Length "new movies in the last" $days "past days"
	foreach($_ in $movies) { Write-Host (get-date) $_.title }
	#load movie thumbs
	$movies=$movies | select *, @{Name="image"; Expression={$bytes=$web.DownloadData($plex+$_.thumb+$token); $bytes=Resize-Image $bytes 200; [Convert]::ToBase64String($bytes)}}
	#load html template
	$html=Get-Content $htmlTemplate
	#replace header template
	$html=[Regex]::Replace($html,"<!-- #1(.+?)-->", {$args[0].Groups[1].Value -F $servername,(get-date).Date});
	#write-host $html;
	#replace body template
	$html=[Regex]::Replace($html,"<!-- #2(.+?)-->", {$temp=$args[0].Groups[1].Value; $movies | foreach {$temp -F $_.link, $_.image, $_.title, $_.year, $_.duration, $_.genre, $_.tagline, $_.rating, $_.director, $_.writer, $_.role, $_.summary, $_.released, $_.country, $_.addedAt }})
	#write html result
	$html | Set-Content $htmlOutput
	Write-Host (get-date) "The html report has been generated"
}
