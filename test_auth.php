<?php
$ch = curl_init('http://dotnet:8080/api/v1/auth/validate');
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_POST, true);
curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
$payload = json_encode(['email' => 'eroerick@hotmail.com', 'password' => 'Soyelero12#$']);
echo 'Payload: ' . $payload . PHP_EOL;
curl_setopt($ch, CURLOPT_POSTFIELDS, $payload);
$response = curl_exec($ch);
$code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
echo 'HTTP: ' . $code . PHP_EOL;
echo 'Response: ' . $response . PHP_EOL;
