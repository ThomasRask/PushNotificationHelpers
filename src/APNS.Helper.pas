unit APNS.Helper;

interface

uses
  System.SysUtils, System.Net.HttpClient, System.Net.URLClient,
  System.Net.HttpClientComponent, System.Classes, System.DateUtils,
  Winapi.Windows,
  JOSE.Core.JWT, JOSE.Core.JWS, JOSE.Core.JWK, JOSE.Core.JWA,
  JOSE.Types.JSON, JOSE.Types.Bytes;

type
  TServerType = (stSandbox, stProduction);

  TAPNSHelper = class
  private
    class function GenerateJWT(const AKeyID, ATeamID, AKeyPath: string;
      var Error: string): string;
    class function BuildPayload(const AAlert, ATitle: string; ABadge: Integer;
      const ASound: string; const ACustomData: TJSONObject): string;
    class procedure Log(const AMessage: string);
    class function ValidateDeviceToken(const AToken: string): Boolean;
  public
    /// <summary>
    /// Sends a push notification using Apple Push Notification Service (APNs) over HTTP/2 with JWT authentication.
    /// </summary>
    /// <param name="ADeviceToken">The target device token to which the notification should be sent.</param>
    /// <param name="ABundleID">The app's bundle identifier registered in the Apple Developer portal.</param>
    /// <param name="AKeyID">The Key ID associated with the .p8 private key generated in the Apple Developer account.</param>
    /// <param name="ATeamID">The Team ID of your Apple Developer account.</param>
    /// <param name="AKeyPath">The file path to the .p8 private key.</param>
    /// <param name="AAlert">The body text of the notification message.</param>
    /// <param name="ATitle">The title text of the notification message.</param>
    /// <param name="ABadge">The number to display as the app's icon badge.</param>
    /// <param name="ASound">The name of the sound file to play when the notification is received (e.g., "default").</param>
    /// <param name="AServerType">The target APNs environment – either production or sandbox. Default is production.</param>
	/// <param name="ACustomData">Additional custom data as JSON (optional). Example CustomData.AddPair('action', 'open_screen'); CustomData.AddPair('id', '12345');</param>
    /// <returns>A string with the APNs response (e.g., "OK" or error message).</returns>
	class function SendPushNotification(const ADeviceToken, ABundleID, AKeyID, ATeamID, AKeyPath: string;
      const AAlert, ATitle: string; ABadge: Integer; const ASound: string; 
	  AServerType: TServerType = TServerType.stProduction; ACustomData: TJSONObject = nil): string;
  end;

implementation

uses
  System.IOUtils, System.RegularExpressions;
  
const
  APNS_URL_PROD = 'https://api.push.apple.com/3/device/';
  APNS_URL_SANDBOX = 'https://api.sandbox.push.apple.com/3/device/';
  
class procedure TAPNSHelper.Log(const AMessage: string);
begin
{$IFDEF DEBUG}
  OutputDebugString(PChar(FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + ' [APNS] ' + AMessage));
{$ENDIF}
  // TFile.AppendAllText('apns_log.txt', AMessage + sLineBreak, TEncoding.UTF8);
end;

class function TAPNSHelper.ValidateDeviceToken(const AToken: string): Boolean;
begin
  Result := TRegEx.IsMatch(AToken, '^[a-fA-F0-9]{64}$');
end;
  
class function TAPNSHelper.GenerateJWT(const AKeyID, ATeamID, AKeyPath: string; 
  var Error: string): string;
var
  LToken: TJWT;
  LSigner: TJWS;
  LKey: TJWK;
  KeyContent: string;
begin
  Result := '';
  try
    if not FileExists(AKeyPath) then
    begin
      Error := 'Key file not found: ' + AKeyPath;
      Exit;
    end;

	KeyContent := TFile.ReadAllText(AKeyPath, TEncoding.UTF8);
    if KeyContent.IsEmpty then
    begin
      Error := 'Key file is empty';
      Exit;
    end;
	
    LToken := TJWT.Create;
    try
      LToken.Header.JSON.AddPair('alg', 'ES256');
      LToken.Header.JSON.AddPair('kid', AKeyID);
      LToken.Claims.Issuer := ATeamID;
      LToken.Claims.IssuedAt := Now;
      LToken.Claims.Expiration := IncMinute(Now, 60);

      LSigner := TJWS.Create(LToken);
      try
        LKey := TJWK.Create(KeyContent);
        try
          LSigner.SkipKeyValidation := True;
          LSigner.Sign(LKey, TJOSEAlgorithmId.ES256);
          Result := LSigner.CompactToken;
        finally
          LKey.Free;
        end;
      finally
        LSigner.Free;
      end;
    finally
      LToken.Free;
    end;
  except
    on E: Exception do
    begin
      Error := 'JWT generation error: ' + E.Message;
      Log(Error);
    end;
  end;
end;

class function TAPNSHelper.BuildPayload(const AAlert, ATitle: string; ABadge: Integer;
  const ASound: string; const ACustomData: TJSONObject): string;
var
  AJsonAlert, AJsonAps, AJsonPayload: TJSONObject;
begin
  AJsonAlert := TJSONObject.Create;
  AJsonAps := TJSONObject.Create;
  AJsonPayload := TJSONObject.Create;
  try
    // Sestavení JSON struktury
    AJsonAlert.AddPair('title', ATitle);
    AJsonAlert.AddPair('body', AAlert);

    AJsonAps.AddPair('alert', AJsonAlert);
    AJsonAps.AddPair('badge', TJSONNumber.Create(ABadge));
    AJsonAps.AddPair('sound', ASound);

    AJsonPayload.AddPair('aps', AJsonAps);

    // Přidání custom dat pokud jsou k dispozici
    if Assigned(ACustomData) then
    begin
      var Enum := ACustomData.GetEnumerator;
      try
        while Enum.MoveNext do
          AJsonPayload.AddPair(Enum.Current.JsonString.Value, Enum.Current.JsonValue.Clone as TJSONValue);
      finally
        Enum.Free;
      end;
    end;

    Result := AJsonPayload.ToString;
  finally
    AJsonPayload.Free; // Toto automaticky uvolní i AJsonAps a AJsonAlert
  end;
end;

class function TAPNSHelper.SendPushNotification(const ADeviceToken, ABundleID, AKeyID, ATeamID, AKeyPath: string;
  const AAlert, ATitle: string; ABadge: Integer; const ASound: string; 
  AServerType: TServerType = TServerType.stProduction; ACustomData: TJSONObject = nil): string;
var
  Http: THTTPClient;
  Resp: IHTTPResponse;
  URL, Token, JWTError: string;
  Headers: TNetHeaders;
  Payload: TStringStream;
begin
  try
    if not ValidateDeviceToken(ADeviceToken) then
    begin
      Result := 'Error: Invalid device token format';
      Log(Result);
      Exit;
    end;

    if ABundleID.IsEmpty then
    begin
      Result := 'Error: Bundle ID is empty';
      Log(Result);
      Exit;
    end;

    Token := GenerateJWT(AKeyID, ATeamID, AKeyPath, JWTError);
    if Token.IsEmpty then
    begin
      Result := 'Error: ' + JWTError;
      Exit;
    end;

    if AServerType = TServerType.stSandbox then
      URL := APNS_URL_SANDBOX + ADeviceToken
    else
      URL := APNS_URL_PROD + ADeviceToken;
	  
    Log(Format('Sending to: %s (%s)', [URL, ABundleID]));	  

    Http := THTTPClient.Create;
    try
      Http.ProtocolVersion := THTTPProtocolVersion.HTTP_2_0;
      Http.SecureProtocols := [THTTPSecureProtocol.TLS12, THTTPSecureProtocol.TLS13];
      Http.ConnectionTimeout := 10000;
      Http.ResponseTimeout := 10000;

      SetLength(Headers, 3);
      Headers[0] := TNetHeader.Create('authorization', 'bearer ' + Token);
      Headers[1] := TNetHeader.Create('apns-topic', ABundleID);
      Headers[2] := TNetHeader.Create('apns-push-type', 'alert');

      Payload := TStringStream.Create(BuildPayload(AAlert, ATitle, ABadge, ASound, ACustomData), TEncoding.UTF8);
      try
	      Log('Payload: ' + Payload.DataString);

        Resp := Http.Post(URL, Payload, nil, Headers);

        if Resp.StatusCode = 200 then
	    	begin
          Result := 'OK';
	    	  Log('Notification sent successfully');
	    	end
        else
	    	begin
          Result := Format('Error %d: %s', [Resp.StatusCode, Resp.ContentAsString]);
		      Log(Result);
		    end;
      finally
        Payload.Free;
      end;
    finally
      Http.Free;
    end;
  except
    on E: ENetHTTPClientException do
    begin
      Result := Format('Exception: %s', [E.Message]);
      Log(Result);
    end;
    on E: Exception do
    begin
      Result := 'Exception: ' + E.Message;
      Log(Result);
    end;
  end;  
end;

end.
