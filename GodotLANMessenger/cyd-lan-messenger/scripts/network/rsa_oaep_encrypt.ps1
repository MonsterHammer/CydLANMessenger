param(
	[string]$PublicKeyPath,
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

function Test-RsaPublicSequence([byte[]]$data, [int]$valueOffset, [int]$length) {
	try {
		$testOffset = [ref]$valueOffset
		$end = $valueOffset + $length
		if ($testOffset.Value -ge $end) {
			return $false
		}
		$first = Read-Asn1Tlv $data $testOffset
		if ($first.Tag -ne 0x02 -or $testOffset.Value -ge $end) {
			return $false
		}
		$second = Read-Asn1Tlv $data $testOffset
		return $second.Tag -eq 0x02
	} catch {
		return $false
	}
}

function Find-RsaSequence([byte[]]$data) {
	$offset = [ref]0
	$outer = Read-Asn1Tlv $data $offset
	if ($outer.Tag -ne 0x30) {
		return $null
	}
	if (Test-RsaPublicSequence $data $outer.ValueOffset $outer.Length) {
		return $data
	}

	$childOffset = [ref]$outer.ValueOffset
	$end = $outer.ValueOffset + $outer.Length
	while ($childOffset.Value -lt $end) {
		$childStart = $childOffset.Value
		$child = Read-Asn1Tlv $data $childOffset
		if ($child.Tag -eq 0x03 -and $child.Length -gt 1) {
			$bitStringValue = Copy-Bytes $data ($child.ValueOffset + 1) ($child.Length - 1)
			$found = Find-RsaSequence $bitStringValue
			if ($found -ne $null) {
				return $found
			}
		} elseif ($child.Tag -eq 0x30) {
			$sequenceBytes = Copy-Bytes $data $childStart ($childOffset.Value - $childStart)
			$found = Find-RsaSequence $sequenceBytes
			if ($found -ne $null) {
				return $found
			}
		}
	}
	return $null
}

function Get-RsaPublicNumbers([byte[]]$der) {
	$inner = Find-RsaSequence $der
	if ($inner -eq $null) {
		throw "RSA public key sequence not found"
	}
	$rsaOffset = [ref]0
	$rsaSeq = Read-Asn1Tlv $inner $rsaOffset
	if ($rsaSeq.Tag -ne 0x30) {
		throw "Expected RSA SEQUENCE"
	}
	$rsaOffset = [ref]$rsaSeq.ValueOffset
	$modulus = Read-Asn1Integer $inner $rsaOffset
	$exponent = Read-Asn1Integer $inner $rsaOffset
	return @{ Modulus = $modulus; Exponent = $exponent }
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

function Encode-OaepSha1([byte[]]$message, [int]$k) {
	$hashLength = 20
	if ($message.Length -gt ($k - (2 * $hashLength) - 2)) {
		throw "Message too long for RSA OAEP"
	}
	$lHash = Get-Sha1 ([byte[]]@())
	$psLength = $k - $message.Length - (2 * $hashLength) - 2
	$db = New-Object byte[] ($hashLength + $psLength + 1 + $message.Length)
	[Array]::Copy($lHash, 0, $db, 0, $hashLength)
	$db[$hashLength + $psLength] = 1
	[Array]::Copy($message, 0, $db, $hashLength + $psLength + 1, $message.Length)

	$seed = New-Object byte[] $hashLength
	$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
	try {
		$rng.GetBytes($seed)
	} finally {
		$rng.Dispose()
	}

	$dbMask = Get-Mgf1 $seed ($k - $hashLength - 1)
	$maskedDb = Invoke-Xor $db $dbMask
	$seedMask = Get-Mgf1 $maskedDb $hashLength
	$maskedSeed = Invoke-Xor $seed $seedMask

	$em = New-Object byte[] $k
	$em[0] = 0
	[Array]::Copy($maskedSeed, 0, $em, 1, $hashLength)
	[Array]::Copy($maskedDb, 0, $em, 1 + $hashLength, $maskedDb.Length)
	return $em
}

$pem = Get-Content -LiteralPath $PublicKeyPath -Raw
$publicNumbers = Get-RsaPublicNumbers (Convert-PemToDer $pem)
$data = [System.IO.File]::ReadAllBytes($DataPath)
$k = $publicNumbers.Modulus.Length
$encoded = Encode-OaepSha1 $data $k

$m = Convert-BigEndianToBigInteger $encoded
$e = Convert-BigEndianToBigInteger $publicNumbers.Exponent
$n = Convert-BigEndianToBigInteger $publicNumbers.Modulus
$c = [System.Numerics.BigInteger]::ModPow($m, $e, $n)
$encrypted = Convert-BigIntegerToBigEndian $c $k
[Convert]::ToBase64String($encrypted)
