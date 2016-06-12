param([String[]] $libraries, [String] $plex="http://localhost:32400", [Int] $days=7, $htmlTemplate=".\PlexNewAddedMoviesTemplate.html", $htmlOutput=".\PlexNewAddedMovies.html")
Add-Type -AssemblyName System.Drawing
Function Convert-FromUnixdate ($UnixDate) { if ($UnixDate -eq $Null) { $Null } else {(get-date "1/1/1970").AddSeconds($UnixDate) }}
Function Resize-Image ($bytes,$width) { $img=[System.Drawing.Image]::FromStream([System.IO.MemoryStream]$bytes); $scale=$width/$img.Width; $newImg = new-object System.Drawing.Bitmap([Int][math]::Floor($scale*$img.Width),[Int][math]::Floor($scale*$img.Height)); $g = [System.Drawing.Graphics]::FromImage($newImg); $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic; $g.DrawImage($img, 0, 0, $newImg.Width, $newImg.Height); $stream = new-object System.IO.MemoryStream; $newImg.Save($stream, [System.Drawing.Imaging.ImageFormat]::Jpeg); $stream.ToArray(); }
$web=New-Object System.Net.WebCLient
$doc=New-Object System.Xml.XmlDocument
#delete old file
If (Test-Path $htmlOutput) { remove-item $htmlOutput }
#get server id and name, required to generate the links
$xml=[xml]$web.DownloadString($plex);
$servername=$xml.MediaContainer.friendlyName
$serverid=$xml.MediaContainer.machineIdentifier;
#get all the library and filter them if $libraries is defined
$dirs=([xml]$web.DownloadString($plex+"/library/sections")).MediaContainer.Directory | where {$libraries -eq $Null -or $libraries -contains $_.title }
#get all  the movies of the libraries
$movies=$dirs | foreach{$xml=[xml]$web.DownloadString(($plex+"/library/sections/{0}/all") -F $_.key); $library=$xml.MediaContainer.librarySectionTitle; $xml.MediaContainer.Video | where {$_.type -eq "movie"} | select -p $library, title, year, tagline, summary, rating, thumb, @{Name="link"; Expression={$plex+"/web/index.html#!/server/"+$serverid+"/details/"+[System.Uri]::EscapeDataString($_.key)}}, @{Name="duration"; Expression={Convert-FromUnixdate($_.duration/1000)}}, @{Name="addedAt"; Expression={Convert-FromUnixdate($_.addedAt)}}, @{Name="released"; Expression={[DateTime]::Parse($_.originallyAvailableAt)}}, @{Name="genre"; Expression={$arr=$_.Genre|foreach{$_.tag}; [System.String]::Join(", ",$arr); }}, @{Name="writer"; Expression={$arr=$_.Writer|foreach{$_.tag}; [System.String]::Join(", ",$arr); }}, @{Name="director"; Expression={$arr=$_.Director|foreach{$_.tag}; [System.String]::Join(", ",$arr); }}, @{Name="country"; Expression={$arr=$_.Country|foreach{$_.tag}; [System.String]::Join(", ",$arr); }}, @{Name="role"; Expression={$arr=$_.Role|foreach{$_.tag}; [System.String]::Join(", ",$arr); }} }
#get only the movies not older than x days
$from=(get-date).Date.AddDays(-$days);
$movies=$movies | where {$_.addedAt -gt $from}
if ($movies.Length -gt 0)
{
	#load movie thumbs
	$movies=$movies | select *, @{Name="image"; Expression={$bytes=$web.DownloadData($plex+$_.thumb); $bytes=Resize-Image $bytes 200; [Convert]::ToBase64String($bytes)}}
	#load html template
	$html=Get-Content $htmlTemplate
	#replace header template
	$html=[Regex]::Replace($html,"<!-- #1(.+?)-->", {$args[0].Groups[1].Value -F $servername,(get-date).Date});
	#write-host $html;
	#replace body template
	$html=[Regex]::Replace($html,"<!-- #2(.+?)-->", {$temp=$args[0].Groups[1].Value; $movies | foreach {$temp -F $_.link, $_.image, $_.title, $_.year, $_.duration, $_.genre, $_.tagline, $_.rating, $_.director, $_.writer, $_.role, $_.summary, $_.released, $_.country, $_.addedAt }})
	#write html result
	$html | Set-Content $htmlOutput
}