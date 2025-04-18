program Example_APNS;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils, APNS.Helper;

begin
  try
    var ResultStr := TAPNSHelper.SendPushNotification(
      'Device Token',
      'Your Budle ID',
      'Your KeyID',
      'Your TeamID',
      'Path to .p8 private key',
      'Hello, World',
      'Title',
      1,
      'default',
      TServerType.stProduction
    );

    Writeln(ResultStr);
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
