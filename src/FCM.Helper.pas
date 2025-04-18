unit FCM.Helper;

interface

uses
  System.SysUtils, System.Classes, System.Net.HttpClient, System.Net.URLClient,
  Winapi.Windows,
  JOSE.Core.JWT, JOSE.Core.JWS, JOSE.Core.JWK, JOSE.Core.JWA,
  JOSE.Types.JSON, JOSE.Types.Bytes, System.DateUtils;

type
  TFCMHelper = class
  private
    class function GenerateJWT(const ServiceAccountJSONPath: string): string;
    class function GetAccessToken(const JWT: string): string;
    class function BuildPayload(const DeviceToken, Title, Body, Data: string): string;
	class procedure Log(const Msg: string);
  public
    /// <summary>
    /// Sends a push notification to an Android device using Firebase Cloud Messaging (FCM) and JWT authentication.
    /// </summary>
    /// <param name="ServiceAccountJSONPath">Path to the Firebase service account JSON key file.</param>
    /// <param name="DeviceToken">FCM device token of the target Android device.</param>
    /// <param name="ProjectID">Firebase project ID associated with your app.</param>
    /// <param name="Title">Title of the notification.</param>
    /// <param name="Body">Body text of the notification.</param>
  	/// <param name="Data">Custom data of the notification. Example {"action":"open_screen","id":"123"}</param>
    /// <returns>Returns the server response as a string, including the HTTP status code and response content.</returns>
    class function SendPushNotification(const ServiceAccountJSONPath, DeviceToken,
      ProjectID, Title, Body: string; Data: string = ''): string;
  end;

implementation

uses
  System.IOUtils, System.NetEncoding;

class procedure TFCMHelper.Log(const Msg: string);
begin
{$IFDEF DEBUG}
  OutputDebugString(PChar(FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + ' [FCM] ' + Msg));
{$ENDIF}
// TFile.AppendAllText('fcm_log.txt', AMessage + sLineBreak, TEncoding.UTF8);
end;

class function TFCMHelper.GenerateJWT(const ServiceAccountJSONPath: string): string;
var
  LToken: TJWT;
  LSigner: TJWS;
  LKey: TJWK;
  JSON, PrivateKey: string;
  JSONObj: TJSONObject;
begin
  try
    JSON := TFile.ReadAllText(ServiceAccountJSONPath, TEncoding.UTF8);
    JSONObj := TJSONObject.ParseJSONValue(JSON) as TJSONObject;
    try
      PrivateKey := JSONObj.GetValue('private_key').Value;

      LToken := TJWT.Create;
      try
        LToken.Header.JSON.AddPair('alg', 'RS256');
        LToken.Header.JSON.AddPair('typ', 'JWT');

        LToken.Claims.IssuedAt := Now;
        LToken.Claims.Expiration := IncHour(Now, 1);
        LToken.Claims.Issuer := JSONObj.GetValue('client_email').Value;
        LToken.Claims.Audience := 'https://oauth2.googleapis.com/token';
        LToken.Claims.JSON.AddPair('scope', 'https://www.googleapis.com/auth/firebase.messaging');

        LSigner := TJWS.Create(LToken);
        try
          LKey := TJWK.Create(PrivateKey);
          try
            LSigner.Sign(LKey, TJOSEAlgorithmId.RS256);
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
    finally
      JSONObj.Free;
    end;
  except
    on E: Exception do
    begin
      Log('JWT generation error: ' + E.Message);
      Result := '';
    end;
  end;
end;

class function TFCMHelper.GetAccessToken(const JWT: string): string;
var
  HTTPClient: THTTPClient;
  Response: IHTTPResponse;
  PostData: TStringStream;
  JSONResponse: TJSONObject;
begin
  HTTPClient := THTTPClient.Create;
  try
    PostData := TStringStream.Create(
      'grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=' + TNetEncoding.URL.Encode(JWT),
      TEncoding.UTF8
    );
    try
      Response := HTTPClient.Post(
        'https://oauth2.googleapis.com/token',
        PostData,
        nil,
        [TNetHeader.Create('Content-Type', 'application/x-www-form-urlencoded')]
      );

      if Response.StatusCode <> 200 then
      begin
        Log('Access token error: ' + Response.StatusCode.ToString + ' - ' + Response.ContentAsString);
        Exit('');
      end;

      JSONResponse := TJSONObject.ParseJSONValue(Response.ContentAsString) as TJSONObject;
      try
        Result := JSONResponse.GetValue('access_token').Value;
      finally
        JSONResponse.Free;
      end;
    finally
      PostData.Free;
    end;
  finally
    HTTPClient.Free;
  end;
end;

class function TFCMHelper.BuildPayload(const DeviceToken, Title, Body, Data: string): string;
var
  Payload, Message, Notification, Android, DataObj: TJSONObject;
begin
  Notification := TJSONObject.Create;
  Notification.AddPair('title', Title);
  Notification.AddPair('body', Body);

  Android := TJSONObject.Create;
  Android.AddPair('priority', 'high');

  Message := TJSONObject.Create;
  Message.AddPair('token', DeviceToken);
  Message.AddPair('notification', Notification);
  Message.AddPair('android', Android);

  if not Data.IsEmpty then
  begin
    DataObj := TJSONObject.ParseJSONValue(Data) as TJSONObject;
    if Assigned(DataObj) then
      Message.AddPair('data', DataObj);
  end;

  Payload := TJSONObject.Create;
  Payload.AddPair('message', Message);

  Result := Payload.ToString;
  Log('Payload built: ' + Result);
end;

class function TFCMHelper.SendPushNotification(const ServiceAccountJSONPath,
  DeviceToken, ProjectID, Title, Body: string; Data: string = ''): string;
var
  JWT, AccessToken, URL: string;
  HTTPClient: THTTPClient;
  Response: IHTTPResponse;
  PostData: TStringStream;
begin
  try
    Log(Format('Sending notification to %s (%s)', [DeviceToken, ProjectID]));
	
    JWT := GenerateJWT(ServiceAccountJSONPath);
    AccessToken := GetAccessToken(JWT);
    URL := Format('https://fcm.googleapis.com/v1/projects/%s/messages:send', [ProjectID]);

    HTTPClient := THTTPClient.Create;
    try
      HTTPClient.ConnectionTimeout := 10000;
      HTTPClient.ResponseTimeout := 10000;

      PostData := TStringStream.Create(BuildPayload(DeviceToken, Title, Body, Data), TEncoding.UTF8);
      try
        Response := HTTPClient.Post(
          URL,
          PostData,
          nil,
          [
            TNetHeader.Create('Authorization', 'Bearer ' + AccessToken),
            TNetHeader.Create('Content-Type', 'application/json')
          ]
        );

        Result := Format('%d - %s', [Response.StatusCode, Response.ContentAsString]);
	      Log('Server response: ' + Result);
      finally
        PostData.Free;
      end;
    finally
      HTTPClient.Free;
    end;
  except
    on E: Exception do
    begin
      Result := 'Exception: ' + E.Message;
      Log('Error: ' + Result);
    end;
  end;
end;

end.
