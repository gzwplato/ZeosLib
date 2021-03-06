{*********************************************************}
{                                                         }
{                 Zeos Database Objects                   }
{         Interbase Database Connectivity Classes         }
{                                                         }
{        Originally written by Sergey Merkuriev           }
{                                                         }
{*********************************************************}

{@********************************************************}
{    Copyright (c) 1999-2012 Zeos Development Group       }
{                                                         }
{ License Agreement:                                      }
{                                                         }
{ This library is distributed in the hope that it will be }
{ useful, but WITHOUT ANY WARRANTY; without even the      }
{ implied warranty of MERCHANTABILITY or FITNESS FOR      }
{ A PARTICULAR PURPOSE.  See the GNU Lesser General       }
{ Public License for more details.                        }
{                                                         }
{ The source code of the ZEOS Libraries and packages are  }
{ distributed under the Library GNU General Public        }
{ License (see the file COPYING / COPYING.ZEOS)           }
{ with the following  modification:                       }
{ As a special exception, the copyright holders of this   }
{ library give you permission to link this library with   }
{ independent modules to produce an executable,           }
{ regardless of the license terms of these independent    }
{ modules, and to copy and distribute the resulting       }
{ executable under terms of your choice, provided that    }
{ you also meet, for each linked independent module,      }
{ the terms and conditions of the license of that module. }
{ An independent module is a module which is not derived  }
{ from or based on this library. If you modify this       }
{ library, you may extend this exception to your version  }
{ of the library, but you are not obligated to do so.     }
{ If you do not wish to do so, delete this exception      }
{ statement from your version.                            }
{                                                         }
{                                                         }
{ The project web site is located on:                     }
{   http://zeos.firmos.at  (FORUM)                        }
{   http://sourceforge.net/p/zeoslib/tickets/ (BUGTRACKER)}
{   svn://svn.code.sf.net/p/zeoslib/code-0/trunk (SVN)    }
{                                                         }
{   http://www.sourceforge.net/projects/zeoslib.          }
{                                                         }
{                                                         }
{                                 Zeos Development Group. }
{********************************************************@}

unit ZDbcInterbase6;

interface

{$I ZDbc.inc}

uses
  Classes, {$IFDEF MSEgui}mclasses,{$ENDIF} SysUtils, Contnrs,
  ZPlainFirebirdDriver, ZCompatibility, ZDbcUtils, ZDbcIntfs,
  ZDbcConnection, ZPlainFirebirdInterbaseConstants, ZSysUtils, ZDbcLogging,
  ZDbcInterbase6Utils, ZDbcGenericResolver, ZTokenizer, ZGenericSqlAnalyser,
  ZURL;

type

  {** Implements Interbase6 Database Driver. }
  {$WARNINGS OFF}
  TZInterbase6Driver = class(TZAbstractDriver)
  public
    constructor Create; override;
    function Connect(const Url: TZURL): IZConnection; override;
    function GetMajorVersion: Integer; override;
    function GetMinorVersion: Integer; override;

    function GetTokenizer: IZTokenizer; override;
    function GetStatementAnalyser: IZStatementAnalyser; override;
  end;
  {$WARNINGS ON}

  {** Represents a Interbase specific connection interface. }
  IZInterbase6Connection = interface (IZConnection)
    ['{E870E4FE-21EB-4725-B5D8-38B8A2B12D0B}']
    function GetDBHandle: PISC_DB_HANDLE;
    function GetTrHandle: PISC_TR_HANDLE;
    function GetDialect: Word;
    function GetPlainDriver: IZInterbasePlainDriver;
    function GetXSQLDAMaxSize: LongWord;
  end;

  {** Implements Interbase6 Database Connection. }

  { TZInterbase6Connection }

  TZInterbase6Connection = class(TZAbstractConnection, IZInterbase6Connection)
  private
    FDialect: Word;
    FHandle: TISC_DB_HANDLE;
    FTrHandle: TISC_TR_HANDLE;
    FStatusVector: TARRAY_ISC_STATUS;
    FHardCommit: boolean;
    FHostVersion: Integer;
    FXSQLDAMaxSize: LongWord;
    procedure CloseTransaction;
  protected
    procedure InternalCreate; override;
    procedure OnPropertiesChange(Sender: TObject); override;
  public
    procedure StartTransaction;
    procedure SetTransactionIsolation(Level: TZTransactIsolationLevel); override;
    function GetHostVersion: Integer; override;
    function GetDBHandle: PISC_DB_HANDLE;
    function GetTrHandle: PISC_TR_HANDLE;
    function GetDialect: Word;
    function GetXSQLDAMaxSize: LongWord;
    function GetPlainDriver: IZInterbasePlainDriver;
    procedure CreateNewDatabase(const SQL: RawByteString);

    function CreateRegularStatement(Info: TStrings): IZStatement; override;
    function CreatePreparedStatement(const SQL: string; Info: TStrings):
      IZPreparedStatement; override;
    function CreateCallableStatement(const SQL: string; Info: TStrings):
      IZCallableStatement; override;

    function CreateSequence(const Sequence: string; BlockSize: Integer):
      IZSequence; override;

    procedure SetReadOnly(Value: Boolean); override;

    procedure Commit; override;
    procedure Rollback; override;

    function PingServer: Integer; override;

    procedure Open; override;
    procedure Close; override;

    function GetBinaryEscapeString(const Value: RawByteString): String; override;
    function GetBinaryEscapeString(const Value: TBytes): String; override;
    function GetEscapeString(const Value: RawByteString): RawByteString; override;
    function GetEscapeString(const Value: ZWideString): ZWideString; override;
  end;

  {** Implements a specialized cached resolver for Interbase/Firebird. }
  TZInterbase6CachedResolver = class(TZGenericCachedResolver)
  public
    function FormCalculateStatement(Columns: TObjectList): string; override;
  end;

  {** Implements a Interbase 6 sequence. }
  TZInterbase6Sequence = class(TZAbstractSequence)
  public
    function GetCurrentValue: Int64; override;
    function GetNextValue: Int64; override;
    function GetCurrentValueSQL: string; override;
    function GetNextValueSQL: string; override;
  end;


var
  {** The common driver manager object. }
  Interbase6Driver: IZDriver;

implementation

uses ZFastCode, ZDbcInterbase6Statement, ZDbcInterbase6Metadata, ZEncoding,
  ZInterbaseToken, ZInterbaseAnalyser, ZDbcMetadata
  {$IFDEF WITH_UNITANSISTRINGS}, AnsiStrings{$ENDIF};

{ TZInterbase6Driver }

{**
  Attempts to make a database connection to the given URL.
  The driver should return "null" if it realizes it is the wrong kind
  of driver to connect to the given URL.  This will be common, as when
  the JDBC driver manager is asked to connect to a given URL it passes
  the URL to each loaded driver in turn.

  <P>The driver should raise a SQLException if it is the right
  driver to connect to the given URL, but has trouble connecting to
  the database.

  <P>The java.util.Properties argument can be used to passed arbitrary
  string tag/value pairs as connection arguments.
  Normally at least "user" and "password" properties should be
  included in the Properties.

  @param url the URL of the database to which to connect
  @param info a list of arbitrary string tag/value pairs as
    connection arguments. Normally at least a "user" and
    "password" property should be included.
  @return a <code>Connection</code> object that represents a
    connection to the URL
}
{$WARNINGS OFF}
function TZInterbase6Driver.Connect(const Url: TZURL): IZConnection;
begin
  Result := TZInterbase6Connection.Create(Url);
end;
{$WARNINGS ON}

{**
  Constructs this object with default properties.
}
constructor TZInterbase6Driver.Create;
begin
  inherited Create;
  AddSupportedProtocol(AddPlainDriverToCache(TZInterbase6PlainDriver.Create));
  AddSupportedProtocol(AddPlainDriverToCache(TZFirebird10PlainDriver.Create));
  AddSupportedProtocol(AddPlainDriverToCache(TZFirebird15PlainDriver.Create));
  AddSupportedProtocol(AddPlainDriverToCache(TZFirebird20PlainDriver.Create));
  AddSupportedProtocol(AddPlainDriverToCache(TZFirebird21PlainDriver.Create));
  AddSupportedProtocol(AddPlainDriverToCache(TZFirebird25PlainDriver.Create));
  AddSupportedProtocol(AddPlainDriverToCache(TZFirebird30PlainDriver.Create));
  // embedded drivers
  AddSupportedProtocol(AddPlainDriverToCache(TZFirebirdD15PlainDriver.Create));
  AddSupportedProtocol(AddPlainDriverToCache(TZFirebirdD20PlainDriver.Create));
  AddSupportedProtocol(AddPlainDriverToCache(TZFirebirdD21PlainDriver.Create));
  AddSupportedProtocol(AddPlainDriverToCache(TZFirebirdD25PlainDriver.Create));
  AddSupportedProtocol(AddPlainDriverToCache(TZFirebirdD30PlainDriver.Create));
end;

{**
  Gets the driver's major version number. Initially this should be 1.
  @return this driver's major version number
}
function TZInterbase6Driver.GetMajorVersion: Integer;
begin
 Result := 1;
end;

{**
  Gets the driver's minor version number. Initially this should be 0.
  @return this driver's minor version number
}
function TZInterbase6Driver.GetMinorVersion: Integer;
begin
  Result := 0;
end;

{**
  Gets a SQL syntax tokenizer.
  @returns a SQL syntax tokenizer object.
}
function TZInterbase6Driver.GetTokenizer: IZTokenizer;
begin
  Result := TZInterbaseTokenizer.Create;
end;

{**
  Creates a statement analyser object.
  @returns a statement analyser object.
}
function TZInterbase6Driver.GetStatementAnalyser: IZStatementAnalyser;
begin
  Result := TZInterbaseStatementAnalyser.Create; { thread save! Allways return a new Analyser! }
end;

{ TZInterbase6Connection }

procedure TZInterbase6Connection.CloseTransaction;
begin
  if FTrHandle <> 0 then
  begin
    if AutoCommit then
    begin
      GetPlainDriver.isc_commit_transaction(@FStatusVector, @FTrHandle);
      DriverManager.LogMessage(lcTransaction, ConSettings^.Protocol,
        'COMMIT TRANSACTION "'+ConSettings^.DataBase+'"');
    end
    else
    begin
      GetPlainDriver.isc_rollback_transaction(@FStatusVector, @FTrHandle);
      DriverManager.LogMessage(lcTransaction, ConSettings^.Protocol,
        'ROLLBACK TRANSACTION "'+ConSettings^.DataBase+'"');
    end;
    FTrHandle := 0;
    CheckInterbase6Error(GetPlainDriver, FStatusVector, ConSettings, lcDisconnect);
  end;
end;

{**
  Releases a Connection's database and JDBC resources
  immediately instead of waiting for
  them to be automatically released.

  <P><B>Note:</B> A Connection is automatically closed when it is
  garbage collected. Certain fatal errors also result in a closed
  Connection.
}
procedure TZInterbase6Connection.Close;
begin
  if Closed or (not Assigned(PlainDriver)) then
     Exit;

  CloseTransaction;

  if FHandle <> 0 then
  begin
    GetPlainDriver.isc_detach_database(@FStatusVector, @FHandle);
    FHandle := 0;
    CheckInterbase6Error(GetPlainDriver, FStatusVector, ConSettings, lcDisconnect);
  end;

  DriverManager.LogMessage(lcConnect, ConSettings^.Protocol,
      'DISCONNECT FROM "'+ConSettings^.DataBase+'"');

  inherited Close;
end;

{**
   Commit current transaction
}
procedure TZInterbase6Connection.Commit;
begin
  if Closed then
     Exit;

  if FTrHandle <> 0 then
  begin
    if FHardCommit then
    begin
      GetPlainDriver.isc_commit_transaction(@FStatusVector, @FTrHandle);
      FTrHandle := 0; //normaly not required! Old server code?
    end
    else
      GetPlainDriver.isc_commit_retaining(@FStatusVector, @FTrHandle);

    CheckInterbase6Error(GetPlainDriver, FStatusVector, ConSettings, lcTransaction);
    DriverManager.LogMessage(lcTransaction,
      ConSettings^.Protocol, 'TRANSACTION COMMIT');
  end;
end;

{**
  Constructs this object and assignes the main properties.
}
procedure TZInterbase6Connection.InternalCreate;
var
  RoleName: string;
  ConnectTimeout : integer;
  WireCompression: Boolean;
begin
  Self.FMetadata := TZInterbase6DatabaseMetadata.Create(Self, Url);

  FHardCommit := StrToBoolEx(URL.Properties.Values['hard_commit']);
  { Sets a default Interbase port }

  if Self.Port = 0 then
    Self.Port := 3050;

  { set default sql dialect it can be overriden }
  FDialect := 3;

  FDialect := StrToIntDef(URL.Properties.Values['dialect'], FDialect);

  { Processes connection properties. }
  self.Info.Values['isc_dpb_username'] := Url.UserName;
  self.Info.Values['isc_dpb_password'] := Url.Password;

  if FClientCodePage = '' then //was set on inherited Create(...)
    if URL.Properties.Values['isc_dpb_lc_ctype'] <> '' then //Check if Dev set's it manually
    begin
      FClientCodePage := URL.Properties.Values['isc_dpb_lc_ctype'];
      CheckCharEncoding(FClientCodePage, True);
    end;
  URL.Properties.Values['isc_dpb_lc_ctype'] := FClientCodePage;

  RoleName := Trim(URL.Properties.Values['rolename']);
  if RoleName <> '' then
    URL.Properties.Values['isc_dpb_sql_role_name'] := UpperCase(RoleName);

  ConnectTimeout := StrToIntDef(URL.Properties.Values['timeout'], -1);
  if ConnectTimeout >= 0 then
    URL.Properties.Values['isc_dpb_connect_timeout'] := ZFastCode.IntToStr(ConnectTimeout);

  WireCompression := StrToBoolEx(URL.Properties.Values['wirecompression']);
  if WireCompression then URL.Properties.Add('isc_dpb_config=WireCompression=true');

  FXSQLDAMaxSize := 64*1024; //64KB by default
  FHandle := 0;
end;

procedure TZInterbase6Connection.OnPropertiesChange(Sender: TObject);
begin
  if StrToBoolEx(Info.Values['hard_commit']) <> FHardCommit then
  begin
    if FTrHandle <> 0 then CloseTransaction;
    FHardCommit := StrToBoolEx(Info.Values['hard_commit']);
  end;
end;

{**
  Creates a <code>Statement</code> object for sending
  SQL statements to the database.
  SQL statements without parameters are normally
  executed using Statement objects. If the same SQL statement
  is executed many times, it is more efficient to use a
  <code>PreparedStatement</code> object.
  <P>
  Result sets created using the returned <code>Statement</code>
  object will by default have forward-only type and read-only concurrency.

  @param Info a statement parameters.
  @return a new Statement object
}
function TZInterbase6Connection.CreateRegularStatement(Info: TStrings):
  IZStatement;
begin
  if IsClosed then
     Open;
  Result := TZInterbase6Statement.Create(Self, Info);
end;

{**
  Gets the host's full version number. Initially this should be 0.
  The format of the version returned must be XYYYZZZ where
   X   = Major version
   YYY = Minor version
   ZZZ = Sub version
  @return this server's full version number
}
function TZInterbase6Connection.GetHostVersion: Integer;
begin
  Result := FHostVersion;
end;

{**
   Get database connection handle.
   @return database handle
}
function TZInterbase6Connection.GetDBHandle: PISC_DB_HANDLE;
begin
  Result := @FHandle;
end;

{**
   Return Interbase dialect number. Dialect a dialect Interbase SQL
   must be 1 or 2 or 3.
   @return dialect number
}
function TZInterbase6Connection.GetDialect: Word;
begin
  Result := FDialect;
end;

function TZInterbase6Connection.GetXSQLDAMaxSize: LongWord;
begin
  Result := FXSQLDAMaxSize;
end;

{**
   Return native interbase plain driver
   @return plain driver
}
function TZInterbase6Connection.GetPlainDriver: IZInterbasePlainDriver;
begin
  Result := PlainDriver as IZInterbasePlainDriver;
end;

{**
   Get Interbase transaction handle
   @return transaction handle
}
function TZInterbase6Connection.GetTrHandle: PISC_TR_HANDLE;
begin
  if (FTrHandle = 0) and not Closed then
    StartTransaction;
  Result := @FTrHandle;
end;

{**
  Opens a connection to database server with specified parameters.
}
procedure TZInterbase6Connection.Open;
const sCS_NONE = 'NONE';
var
  DPB: PAnsiChar;
  FDPBLength: Word;
  DBName: array[0..512] of AnsiChar;
  NewDB: RawByteString;
  tmp: String;
  i: Integer;
begin
  if not Closed then
     Exit;

  if TransactIsolationLevel = tiReadUncommitted then
    raise EZSQLException.Create('Isolation level do not capable');
  if ConSettings^.ClientCodePage = nil then
    CheckCharEncoding(FClientCodePage, True);

  DPB := GenerateDPB(Info, FDPBLength{%H-}, FDialect);

  if HostName <> '' then
    if Port <> 3050 then
      {$IFDEF WITH_STRPCOPY_DEPRECATED}AnsiStrings.{$ENDIF}StrPCopy(DBName, ConSettings^.ConvFuncs.ZStringToRaw((HostName + '/' + ZFastCode.IntToStr(Port) + ':' + Database),
            ConSettings^.CTRL_CP, ConSettings^.ClientCodePage^.CP))
    else
      {$IFDEF WITH_STRPCOPY_DEPRECATED}AnsiStrings.{$ENDIF}StrPCopy(DBName, ConSettings^.ConvFuncs.ZStringToRaw((HostName + ':' + Database),
            ConSettings^.CTRL_CP, ConSettings^.ClientCodePage^.CP))
  else
    {$IFDEF WITH_STRPCOPY_DEPRECATED}AnsiStrings.{$ENDIF}StrPCopy(DBName, ConSettings^.Database);

  try
    { Create new db if needed }
    if Info.Values['createNewDatabase'] <> '' then
    begin
      NewDB := ConSettings^.ConvFuncs.ZStringToRaw(Info.Values['createNewDatabase'],
        ConSettings^.CTRL_CP, ConSettings^.ClientCodePage^.CP);
      CreateNewDatabase(NewDB);
      { Logging connection action }
      DriverManager.LogMessage(lcConnect, ConSettings^.Protocol,
        'CREATE DATABASE "'+NewDB+'" AS USER "'+ ConSettings^.User+'"');
      URL.Properties.Values['createNewDatabase'] := '';
    end;
    
    FHandle := 0;
    { Connect to Interbase6 database. }
    GetPlainDriver.isc_attach_database(@FStatusVector,
      ZFastCode.StrLen(DBName), DBName,
        @FHandle, FDPBLength, DPB);

    { Check connection error }
    CheckInterbase6Error(GetPlainDriver, FStatusVector, ConSettings, lcConnect);

    (GetMetadata.GetDatabaseInfo as IZInterbaseDatabaseInfo).CollectServerInformations; //keep this one first!
    tmp := GetMetadata.GetDatabaseInfo.GetDatabaseProductVersion;
    I := ZFastCode.Pos('.', tmp);
    FHostVersion := StrToInt(Copy(tmp, 1, i-1))*1000000;
    if ZFastCode.Pos(' ', tmp) > 0 then //possible beta or alfa release
      tmp := Copy(tmp, i+1, ZFastCode.Pos(' ', tmp)-i-1)
    else
      tmp := Copy(tmp, i+1, Length(tmp)-i);
    FHostVersion := FHostVersion + StrToInt(tmp)*100000;
    if (GetMetadata.GetDatabaseInfo as IZInterbaseDatabaseInfo).HostIsFireBird then
      if (FHostVersion >= 3000000) then FXSQLDAMaxSize := 10*1024*1024; //might be much more! 4GB? 10MB sounds enough / roundtrip

    { Logging connection action }
    DriverManager.LogMessage(lcConnect, ConSettings^.Protocol,
      'CONNECT TO "'+ConSettings^.DataBase+'" AS USER "'+ConSettings^.User+'"');

    { Start transaction }
    if not FHardCommit then
      StartTransaction;

    inherited Open;

    {Check for ClientCodePage: if empty switch to database-defaults
      and/or check for charset 'NONE' which has a different byte-width
      and no conversations where done except the collumns using collations}
    with GetMetadata.GetCollationAndCharSet('', '', '', '') do
    begin
      if Next then
        if FCLientCodePage = '' then
        begin
          FCLientCodePage := GetString(CollationAndCharSetNameIndex);
          if URL.Properties.Values['ResetCodePage'] <> '' then
          begin
            ConSettings^.ClientCodePage := GetIZPlainDriver.ValidateCharEncoding(FClientCodePage);
            ResetCurrentClientCodePage(URL.Properties.Values['ResetCodePage']);
          end
          else
            CheckCharEncoding(FClientCodePage);
        end
        else
          if GetString(CollationAndCharSetNameIndex) = sCS_NONE then
          begin
            if not ( FClientCodePage = sCS_NONE ) then
            begin
              URL.Properties.Values['isc_dpb_lc_ctype'] := sCS_NONE;
              {save the user wanted CodePage-Informations}
              URL.Properties.Values['ResetCodePage'] := FClientCodePage;
              FClientCodePage := sCS_NONE;
              { charset 'NONE' can't convert anything and write 'Data as is'!
                If another charset was set on attaching the Server then all
                column collations are retrieved with newly choosen collation.
                BUT NO string convertations where done! So we need a
                reopen (since we can set the Client-CharacterSet only on
                connecting) to determine charset 'NONE' corectly. Then the column
                collations have there proper CharsetID's to encode all strings
                correctly. }
              Self.Close;
              Self.Open;
              { Create a new PZCodePage for the new environment-variables }
            end
            else
            begin
              if URL.Properties.Values['ResetCodePage'] <> '' then
              begin
                ConSettings^.ClientCodePage := GetIZPlainDriver.ValidateCharEncoding(sCS_NONE);
                ResetCurrentClientCodePage(URL.Properties.Values['ResetCodePage']);
              end
              else
                CheckCharEncoding(sCS_NONE);
            end;
          end
          else
            if URL.Properties.Values['ResetCodePage'] <> '' then
              ResetCurrentClientCodePage(URL.Properties.Values['ResetCodePage']);
      Close;
    end;
    if FClientCodePage = sCS_NONE then
      ConSettings.AutoEncode := True; //Must be set!
  finally
    {$IFDEF WITH_STRDISPOSE_DEPRECATED}AnsiStrings.{$ENDIF}StrDispose(DPB);
  end;
end;

{**
  Creates a <code>PreparedStatement</code> object for sending
  parameterized SQL statements to the database.

  A SQL statement with or without IN parameters can be
  pre-compiled and stored in a PreparedStatement object. This
  object can then be used to efficiently execute this statement
  multiple times.

  <P><B>Note:</B> This method is optimized for handling
  parametric SQL statements that benefit from precompilation. If
  the driver supports precompilation,
  the method <code>prepareStatement</code> will send
  the statement to the database for precompilation. Some drivers
  may not support precompilation. In this case, the statement may
  not be sent to the database until the <code>PreparedStatement</code> is
  executed.  This has no direct effect on users; however, it does
  affect which method throws certain SQLExceptions.

  Result sets created using the returned PreparedStatement will have
  forward-only type and read-only concurrency, by default.

  @param sql a SQL statement that may contain one or more '?' IN
    parameter placeholders
  @return a new PreparedStatement object containing the
    pre-compiled statement
}
function TZInterbase6Connection.CreatePreparedStatement(
  const SQL: string; Info: TStrings): IZPreparedStatement;
begin
  if IsClosed then
     Open;
  Result := TZInterbase6PreparedStatement.Create(Self, SQL, Info);
end;

{**
  Creates a <code>CallableStatement</code> object for calling
  database stored procedures.
  The <code>CallableStatement</code> object provides
  methods for setting up its IN and OUT parameters, and
  methods for executing the call to a stored procedure.

  <P><B>Note:</B> This method is optimized for handling stored
  procedure call statements. Some drivers may send the call
  statement to the database when the method <code>prepareCall</code>
  is done; others
  may wait until the <code>CallableStatement</code> object
  is executed. This has no
  direct effect on users; however, it does affect which method
  throws certain SQLExceptions.

  Result sets created using the returned CallableStatement will have
  forward-only type and read-only concurrency, by default.

  @param sql a SQL statement that may contain one or more '?'
    parameter placeholders. Typically this  statement is a JDBC
    function call escape string.
  @param Info a statement parameters.
  @return a new CallableStatement object containing the
    pre-compiled SQL statement
}
function TZInterbase6Connection.CreateCallableStatement(const SQL: string;
  Info: TStrings): IZCallableStatement;
begin
  if IsClosed then
     Open;
  Result := TZInterbase6CallableStatement.Create(Self, SQL, Info);
end;

{**
  Drops all changes made since the previous
  commit/rollback and releases any database locks currently held
  by this Connection. This method should be used only when auto-
  commit has been disabled.
  @see #setAutoCommit
}
procedure TZInterbase6Connection.Rollback;
begin
  if FTrHandle <> 0 then
  begin
    if FHardCommit then
    begin
      GetPlainDriver.isc_rollback_transaction(@FStatusVector, @FTrHandle);
      FTrHandle := 0;
    end
    else
      GetPlainDriver.isc_rollback_retaining(@FStatusVector, @FTrHandle);
    CheckInterbase6Error(GetPlainDriver, FStatusVector, ConSettings);
    DriverManager.LogMessage(lcTransaction, ConSettings^.Protocol, 'TRANSACTION ROLLBACK');
  end;
end;

{**
  Checks if a connection is still alive by doing a call to isc_database_info
  It does not matter what info we request, we are not looking at it, as long
  as it is something which should _always_ work if the connection is there.
  We check if the error returned is one of the net_* errors described in the
  firebird client documentation (335544721 .. 335544727).
  Returns 0 if the connection is OK
  Returns non zero if the connection is not OK
}
function TZInterbase6Connection.PingServer: integer;
var
  DatabaseInfoCommand: Char;
  Buffer: array[0..IBBigLocalBufferLength - 1] of AnsiChar;
  ErrorCode: ISC_STATUS;
begin
  DatabaseInfoCommand := Char(isc_info_reads);

  ErrorCode := GetPlainDriver.isc_database_info(@FStatusVector, @FHandle, 1, @DatabaseInfoCommand,
                           IBLocalBufferLength, Buffer);

  if (ErrorCode >= 335544721) and (ErrorCode <= 335544727) then
   result := -1
  else
   result := 0;
end;

{**
   Start Interbase transaction
}
procedure TZInterbase6Connection.StartTransaction;
const tpb_Access: array[boolean] of String = ('isc_tpb_write','isc_tpb_read');

{EH: We do NOT handle the isc_tpb_autocommit of FB because we noticed a huge
 performance drop especially for Batch executions. Note Zeos handles one Batch
 Execution as one Update and loops until all batch array are send. FB with this
 param commits after each "execute block" which definitally kills the idea and
 the expected performance!}
//const tpb_AutoCommit: array[boolean] of String = ('','isc_tpb_autocommit');
var
  Params: TStrings;
  PTEB: PISC_TEB;
begin
  if FHandle <> 0 then
  begin
    if FTrHandle <> 0 then
    begin {CLOSE Last Transaction first!}
      GetPlainDriver.isc_commit_transaction(@FStatusVector, @FTrHandle);
      CheckInterbase6Error(GetPlainDriver, FStatusVector, ConSettings, lcTransaction);
      FTrHandle := 0;
    end;
    PTEB := nil;
    Params := TStringList.Create;

    { Set transaction parameters by TransactIsolationLevel }
    Params.Add('isc_tpb_version3');
    case TransactIsolationLevel of
      tiReadCommitted:
        begin
          Params.Add(tpb_Access[ReadOnly]);
          Params.Add('isc_tpb_read_committed');
          Params.Add('isc_tpb_rec_version');
          Params.Add('isc_tpb_nowait');
        end;
      tiRepeatableRead:
        begin
          Params.Add(tpb_Access[ReadOnly]);
          Params.Add('isc_tpb_concurrency');
          Params.Add('isc_tpb_nowait');
        end;
      tiSerializable:
        begin
          Params.Add(tpb_Access[ReadOnly]);
          Params.Add('isc_tpb_consistency');
        end;
      else
      begin
        { Add user defined parameters for transaction }
        if ZFastCode.Pos('isc_tpb_', Info.Text) > 0 then
        begin
          Params.Clear;
          Params.AddStrings(Info);
        end
        else
        begin
          {extend the firebird defaults by ReadOnly}
          Params.Add(tpb_Access[ReadOnly]);
          Params.Add('isc_tpb_concurrency');
          Params.Add('isc_tpb_wait');
        end;
      end;
    end;

    try
      { GenerateTPB return PTEB with null pointer tpb_address from default
        transaction }
      PTEB := GenerateTPB(Params, FHandle);
      GetPlainDriver.isc_start_multiple(@FStatusVector, @FTrHandle, 1, PTEB);
      CheckInterbase6Error(GetPlainDriver, FStatusVector, ConSettings, lcTransaction);
      DriverManager.LogMessage(lcTransaction, ConSettings^.Protocol,
        'TRANSACTION STARTED.');
    finally
      FreeAndNil(Params);
      {$IFDEF WITH_STRDISPOSE_DEPRECATED}AnsiStrings.{$ENDIF}StrDispose(PTEB.tpb_address);
      FreeMem(PTEB);
    end
  end;
end;

procedure TZInterbase6Connection.SetTransactionIsolation(Level: TZTransactIsolationLevel);
begin
  if (Level <> TransactIsolationLevel) and (FHandle <> 0) then
    CloseTransaction;
  Inherited SetTransactionIsolation(Level);
end;

{**
  Creates new database
  @param SQL a sql strinf for creation database
}
procedure TZInterbase6Connection.CreateNewDatabase(const SQL: RawByteString);
var
  TrHandle: TISC_TR_HANDLE;
begin
  TrHandle := 0;
  GetPlainDriver.isc_dsql_execute_immediate(@FStatusVector, @FHandle, @TrHandle,
    0, PAnsiChar(sql), FDialect, nil);
  CheckInterbase6Error(GetPlainDriver, FStatusVector, ConSettings, lcExecute, SQL);
  //disconnect from the newly created database because the connection character set is NONE,
  //which usually nobody wants
  GetPlainDriver.isc_detach_database(@FStatusVector, @FHandle);
  CheckInterbase6Error(GetPlainDriver, FStatusVector, ConSettings, lcExecute, SQL);
end;

function TZInterbase6Connection.GetBinaryEscapeString(const Value: RawByteString): String;
begin
  //http://tracker.firebirdsql.org/browse/CORE-2789
  if EndsWith(GetPlainDriver.GetProtocol, '2.5') then
    if (Length(Value)*2+3) < 32*1024 then
      Result := GetSQLHexString(PAnsiChar(Value), Length(Value))
    else
      raise Exception.Create('Binary data out of range! Use parameters!')
  else
    raise Exception.Create('Your Firebird-Version does''t support Binary-Data in SQL-Statements! Use parameters!');
end;

function TZInterbase6Connection.GetBinaryEscapeString(const Value: TBytes): String;
begin
  //http://tracker.firebirdsql.org/browse/CORE-2789
  if EndsWith(GetPlainDriver.GetProtocol, '2.5') then
    if (Length(Value)*2+3) < 32*1024 then
      Result := GetSQLHexString(PAnsiChar(Value), Length(Value))
    else
      raise Exception.Create('Binary data out of range! Use parameters!')
  else
    raise Exception.Create('Your Firebird-Version does''t support Binary-Data in SQL-Statements! Use parameters!');
end;

function TZInterbase6Connection.GetEscapeString(const Value: RawByteString): RawByteString;
begin
  //http://www.firebirdsql.org/manual/qsg10-firebird-sql.html
  if GetAutoEncodeStrings then
    if StartsWith(Value, RawByteString('''')) and EndsWith(Value, RawByteString('''')) then
      {$IFDEF UNICODE}
      Result := Value
      {$ELSE}
      Result := GetDriver.GetTokenizer.GetEscapeString(Value)
      {$ENDIF}
    else
      {$IFDEF UNICODE}
      Result := #39+{$IFDEF WITH_UNITANSISTRINGS}AnsiStrings.{$ENDIF}StringReplace(Value, #39, #39#39, [rfReplaceAll])+#39
      {$ELSE}
      Result := GetDriver.GetTokenizer.GetEscapeString(#39+StringReplace(Value, #39, #39#39, [rfReplaceAll])+#39)
      {$ENDIF}
  else
    if StartsWith(Value, RawByteString('''')) and EndsWith(Value, RawByteString('''')) then
      Result := Value
    else
      Result := #39+{$IFDEF WITH_UNITANSISTRINGS}AnsiStrings.{$ENDIF}StringReplace(Value, #39, #39#39, [rfReplaceAll])+#39;
end;

function TZInterbase6Connection.GetEscapeString(const Value: ZWideString): ZWideString;
begin
  //http://www.firebirdsql.org/manual/qsg10-firebird-sql.html
  if GetAutoEncodeStrings then
    if StartsWith(Value, ZWideString('''')) and EndsWith(Value, ZWideString('''')) then
      {$IFDEF UNICODE}
      Result := GetDriver.GetTokenizer.GetEscapeString(Value)
      {$ELSE}
      Result := Value
      {$ENDIF}
    else
      {$IFDEF UNICODE}
      Result := GetDriver.GetTokenizer.GetEscapeString(#39+StringReplace(Value, #39, #39#39, [rfReplaceAll])+#39)
      {$ELSE}
      Result := ConSettings^.ConvFuncs.ZRawToUnicode(GetDriver.GetTokenizer.GetEscapeString(#39+StringReplace(ConSettings^.ConvFuncs.ZUnicodeToRaw(Value, ConSettings^.ClientCodePage^.CP), #39, #39#39, [rfReplaceAll])+#39), ConSettings^.ClientCodePage^.CP)
      {$ENDIF}
  else
    if StartsWith(Value, ZWideString('''')) and EndsWith(Value, ZWideString('''')) then
      Result := Value
    else
      {$IFDEF UNICODE}
      Result := #39+StringReplace(Value, #39, #39#39, [rfReplaceAll])+#39;
      {$ELSE}
      Result := ConSettings^.ConvFuncs.ZRawToUnicode(#39+StringReplace(ConSettings^.ConvFuncs.ZUnicodeToRaw(Value, ConSettings^.ClientCodePage^.CP), #39, #39#39, [rfReplaceAll])+#39, ConSettings^.ClientCodePage^.CP);
      {$ENDIF}
end;
{**
  Creates a sequence generator object.
  @param Sequence a name of the sequence generator.
  @param BlockSize a number of unique keys requested in one trip to SQL server.
  @returns a created sequence object.
}
function TZInterbase6Connection.CreateSequence(const Sequence: string;
  BlockSize: Integer): IZSequence;
begin
  Result := TZInterbase6Sequence.Create(Self, Sequence, BlockSize);
end;

procedure TZInterbase6Connection.SetReadOnly(Value: Boolean);
begin
  if (ReadOnly <> Value) and (FTrHandle <> 0) then
    CloseTransaction;
  ReadOnly := Value;
end;

{ TZInterbase6CachedResolver }

{**
  Forms a where clause for SELECT statements to calculate default values.
  @param Columns a collection of key columns.
  @param OldRowAccessor an accessor object to old column values.
}
function TZInterbase6CachedResolver.FormCalculateStatement(
  Columns: TObjectList): string;
// --> ms, 30/10/2005
var
   iPos: Integer;
begin
  Result := inherited FormCalculateStatement(Columns);
  if Result <> '' then
  begin
    iPos := ZFastCode.pos('FROM', uppercase(Result));
    if iPos > 0 then
      Result := copy(Result, 1, iPos+3) + ' RDB$DATABASE'
    else
      Result := Result + ' FROM RDB$DATABASE';
  end;
// <-- ms
end;

{ TZInterbase6Sequence }

{**
  Gets the current unique key generated by this sequence.
  @param the next generated unique key.
}
function TZInterbase6Sequence.GetCurrentValue: Int64;
var
  Statement: IZStatement;
  ResultSet: IZResultSet;
begin
  Statement := Connection.CreateStatement;
  ResultSet := Statement.ExecuteQuery(Format(
    'SELECT GEN_ID("%s", 0) FROM rdb$generators ' +
    'WHERE rdb$generators.rdb$generator_name = ''%s''', [Name, Name]));
  if ResultSet.Next then
    Result := ResultSet.GetLong(1)
  else
    Result := inherited GetCurrentValue;
  ResultSet.Close;
  Statement.Close;
end;

{**
  Gets the next unique key generated by this sequence.
  @param the next generated unique key.
}
function TZInterbase6Sequence.GetCurrentValueSQL: string;
begin
  Result := Format(' GEN_ID("%s", 0) ', [Name]);
end;

function TZInterbase6Sequence.GetNextValue: Int64;
var
  Statement: IZStatement;
  ResultSet: IZResultSet;
begin
  Statement := Connection.CreateStatement;
  ResultSet := Statement.ExecuteQuery(Format(
    'SELECT GEN_ID("%s", %d) FROM rdb$generators ' +
    'WHERE rdb$generators.rdb$generator_name = ''%s''', [Name, BlockSize, Name]));
  if ResultSet.Next then
    Result := ResultSet.GetLong(1)
  else
    Result := inherited GetNextValue;
  ResultSet.Close;
  Statement.Close;
end;

function TZInterbase6Sequence.GetNextValueSQL: string;
begin
  Result := Format(' GEN_ID("%s", %d) ', [Name, BlockSize]);
end;

initialization
  Interbase6Driver := TZInterbase6Driver.Create;
  DriverManager.RegisterDriver(Interbase6Driver);

finalization
  if Assigned(DriverManager) then
    DriverManager.DeregisterDriver(Interbase6Driver);
  Interbase6Driver := nil;
end.
