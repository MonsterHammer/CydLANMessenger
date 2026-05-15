param(
	[string]$PrivateKeyPath,
	[string]$DataPath
)

$ErrorActionPreference = "Stop"

function Convert-PemToDer([string]$pem) {
	$body = ($pem -split "`r?`n" | Where-Object {
		$_ -and -not $_.StartsWith("-----")
	}) -join ""
	return [Convert]::FromBase64String($body)
}

function Read-Asn1Tlv([byte[]]$data, [ref]$offset) {
	$tag = $data[$offset.Value]
	$offset.Value++
	$lengthByte = $data[$offset.Value]
	$offset.Value++
	if (($lengthByte -band 0x80) -eq 0) {
		$length = $lengthByte
	} else {
		$count = $lengthByte -band 0x7F
		$length = 0
		for ($i = 0; $i -lt $count; $i++) {
			$length = ($length -shl 8) -bor $data[$offset.Value]
			$offset.Value++
		}
	}
	$valueOffset = $offset.Value
	$offset.Value += $length
	return @{ Tag = $tag; Length = $length; ValueOffset = $valueOffset }
}

function Read-Asn1Integer([byte[]]$data, [ref]$offset) {
	$tlv = Read-Asn1Tlv $data $offset
	if ($tlv.Tag -ne 0x02) {
		throw "Expected ASN.1 INTEGER"
	}
	$value = New-Object byte[] $tlv.Length
	[Array]::Copy($data, $tlv.ValueOffset, $value, 0, $tlv.Length)
	while ($value.Length -gt 1 -and $value[0] -eq 0) {
		$trimmed = New-Object byte[] ($value.Length - 1)
		[Array]::Copy($value, 1, $trimmed, 0, $trimmed.Length)
		$value = $trimmed
	}
	return $value
}

function Copy-Bytes([byte[]]$data, [int]$offset, [int]$length) {
	$result = New-Object byte[] $length
	[Array]::Copy($data, $offset, $result, 0, $length)
	return $result
}

function Get-Sha1([byte[]]$data) {
	$sha1 = [System.Security.Cryptography.SHA1]::Create()
	try {
		return $sha1.ComputeHash($data)
	} finally {
		$sha1.Dispose()
	}
}

function Get-Mgf1([byte[]]$seed, [int]$length) {
	$output = New-Object byte[] $length
	$written = 0
	$counter = 0
	while ($written -lt $length) {
		$c = [byte[]]@(
			(($counter -shr 24) -band 0xFF),
			(($counter -shr 16) -band 0xFF),
			(($counter -shr 8) -band 0xFF),
			($counter -band 0xFF)
		)
		$input = New-Object byte[] ($seed.Length + 4)
		[Array]::Copy($seed, 0, $input, 0, $seed.Length)
		[Array]::Copy($c, 0, $input, $seed.Length, 4)
		$digest = Get-Sha1 $input
		$count = [Math]::Min($digest.Length, $length - $written)
		[Array]::Copy($digest, 0, $output, $written, $count)
		$written += $count
		$counter++
	}
	return $output
}

function Invoke-Xor([byte[]]$a, [byte[]]$b) {
	$result = New-Object byte[] $a.Length
	for ($i = 0; $i -lt $a.Length; $i++) {
		$result[$i] = $a[$i] -bxor $b[$i]
	}
	return $result
}

function Decode-OaepSha1([byte[]]$em, [int]$k) {
	$hashLength = 20
	if ($em.Length -ne $k -or $em[0] -ne 0) {
		throw "OAEP decode: bad first byte or length"
	}
	$maskedSeed = Copy-Bytes $em 1 $hashLength
	$maskedDb = Copy-Bytes $em (1 + $hashLength) ($k - $hashLength - 1)

	$seedMask = Get-Mgf1 $maskedDb $hashLength
	$seed = Invoke-Xor $maskedSeed $seedMask
	$dbMask = Get-Mgf1 $seed ($k - $hashLength - 1)
	$db = Invoke-Xor $maskedDb $dbMask

	$lHash = Copy-Bytes $db 0 $hashLength
	$expectedHash = Get-Sha1 ([byte[]]@())
	for ($i = 0; $i -lt $hashLength; $i++) {
		if ($lHash[$i] -ne $expectedHash[$i]) {
			throw "OAEP decode: lHash mismatch"
		}
	}
	$msgStart = $hashLength
	while ($msgStart -lt $db.Length -and $db[$msgStart] -eq 0) {
		$msgStart++
	}
	if ($msgStart -ge $db.Length -or $db[$msgStart] -ne 1) {
		throw "OAEP decode: separator not found"
	}
	$msgStart++
	$message = Copy-Bytes $db $msgStart ($db.Length - $msgStart)
	return $message
}

function Convert-BigEndianToBigInteger([byte[]]$bytes) {
	$little = New-Object byte[] ($bytes.Length + 1)
	for ($i = 0; $i -lt $bytes.Length; $i++) {
		$little[$i] = $bytes[$bytes.Length - 1 - $i]
	}
	$little[$bytes.Length] = 0
	return [System.Numerics.BigInteger]::new($little)
}

function Convert-BigIntegerToBigEndian([System.Numerics.BigInteger]$value, [int]$length) {
	$little = $value.ToByteArray()
	$result = New-Object byte[] $length
	for ($i = 0; $i -lt $little.Length -and $i -lt $length; $i++) {
		$result[$length - 1 - $i] = $little[$i]
	}
	return $result
}

function Get-RsaPrivateComponents([byte[]]$der) {
	$offset = [ref]0
	$outer = Read-Asn1Tlv $der $offset
	if ($outer.Tag -ne 0x30) {
		throw "Expected SEQUENCE"
	}
	$innerOffset = [ref]$outer.ValueOffset
	$version = Read-Asn1Integer $der $innerOffset
	$n = Read-Asn1Integer $der $innerOffset
	$e = Read-Asn1Integer $der $innerOffset
	$d = Read-Asn1Integer $der $innerOffset
	return @{ Modulus = $n; PrivateExponent = $d }
}

$pem = Get-Content -LiteralPath $PrivateKeyPath -Raw
$privateComponents = Get-RsaPrivateComponents (Convert-PemToDer $pem)

$cipher = [System.IO.File]::ReadAllBytes($DataPath)
$k = $privateComponents.Modulus.Length

$c = Convert-BigEndianToBigInteger $cipher
$d = Convert-BigEndianToBigInteger $privateComponents.PrivateExponent
$n = Convert-BigEndianToBigInteger $privateComponents.Modulus
$m = [System.Numerics.BigInteger]::ModPow($c, $d, $n)
$em = Convert-BigIntegerToBigEndian $m $k

$message = Decode-OaepSha1 $em $k
[Convert]::ToBase64String($message)
