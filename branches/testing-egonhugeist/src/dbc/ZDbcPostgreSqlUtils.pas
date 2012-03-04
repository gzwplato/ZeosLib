{*********************************************************}
{                                                         }
{                 Zeos Database Objects                   }
{         PostgreSQL Database Connectivity Classes        }
{                                                         }
{         Originally written by Sergey Seroukhov          }
{                           and Sergey Merkuriev          }
{                                                         }
{*********************************************************}

{@********************************************************}
{    Copyright (c) 1999-2006 Zeos Development Group       }
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
{   http://zeosbugs.firmos.at (BUGTRACKER)                }
{   svn://zeos.firmos.at/zeos/trunk (SVN Repository)      }
{                                                         }
{   http://www.sourceforge.net/projects/zeoslib.          }
{   http://www.zeoslib.sourceforge.net                    }
{                                                         }
{                                                         }
{                                                         }
{                                 Zeos Development Group. }
{********************************************************@}

unit ZDbcPostgreSqlUtils;

interface

{$I ZDbc.inc}

uses
  Classes, SysUtils, ZDbcIntfs, ZPlainPostgreSqlDriver,
  ZDbcPostgreSql, ZDbcLogging;

{**
  Indicate what field type is a number (integer, float and etc.)
  @param  the SQLType field type value
  @result true if field type number
}
function IsNumber(Value: TZSQLType): Boolean;

{**
   Return ZSQLType from PostgreSQL type name
   @param Connection a connection to PostgreSQL
   @param The TypeName is PostgreSQL type name
   @return The ZSQLType type
}
function PostgreSQLToSQLType(Connection: IZPostgreSQLConnection;
  TypeName: string): TZSQLType; overload;

{**
    Another version of PostgreSQLToSQLType()
      - comparing integer should be faster than AnsiString?
   Return ZSQLType from PostgreSQL type name
   @param Connection a connection to PostgreSQL
   @param TypeOid is PostgreSQL type OID
   @return The ZSQLType type
}
function PostgreSQLToSQLType(Connection: IZPostgreSQLConnection;
  TypeOid: Integer): TZSQLType; overload;

{**
  Converts an string into escape PostgreSQL format.
  @param Value a regular string.
  @return a string in PostgreSQL escape format.
}
function EncodeString(const Value: string): string; overload;

{**
  add by Perger -> based on SourceForge:
  [ 1520587 ] Fix for 1484704: bytea corrupted on post when not using utf8,
  file: 1484704.patch

  Converts a binary string into escape PostgreSQL format.
  @param Value a binary stream.
  @return a string in PostgreSQL binary string escape format.
}
{$IFDEF CHECK_CLIENT_CODE_PAGE}
function EncodeBinaryString(const Value: AnsiString): AnsiString;
{$ELSE}
function EncodeBinaryString(const Value: string): string;
{$ENDIF}

{**
  Determine the character code in terms of enumerated number.
  @param InputString the input string.
  @return the character code in terms of enumerated number.
}
{$IFNDEF CHECK_CLIENT_CODE_PAGE}
function pg_CS_code(const InputString: string): TZPgCharactersetType;
{$ENDIF}
{**
  Encode string which probably consists of multi-byte characters.
  Characters ' (apostraphy), low value (value zero), and \ (back slash) are encoded. Since we have noticed that back slash is the second byte of some BIG5 characters (each of them is two bytes in length), we need a characterset aware encoding function.
  @param CharactersetCode the characterset in terms of enumerate code.
  @param Value the regular string.
  @return the encoded string.
}
function EncodeString(CharactersetCode: TZPgCharactersetType; const Value: string): string; overload;

{**
  Converts an string from escape PostgreSQL format.
  @param Value a string in PostgreSQL escape format.
  @return a regular string.
}
function DecodeString(const Value: AnsiString): AnsiString;

{**
  Checks for possible sql errors.
  @param Connection a reference to database connection to execute Rollback.
  @param PlainDriver a PostgreSQL plain driver.
  @param Handle a PostgreSQL connection reference.
  @param LogCategory a logging category.
  @param LogMessage a logging message.
  @param ResultHandle the Handle to the Result
}

procedure CheckPostgreSQLError(Connection: IZConnection;
  PlainDriver: IZPostgreSQLPlainDriver;
  Handle: PZPostgreSQLConnect; LogCategory: TZLoggingCategory;
  const LogMessage: string;
  ResultHandle: PZPostgreSQLResult);


{**
   Resolve problem with minor version in PostgreSql bettas
   @param Value a minor version string like "4betta2"
   @return a miror version number
}
function GetMinorVersion(const Value: string): Word;

implementation

uses ZMessages, ZCompatibility;

type

pg_CS = record
  name: string;
  code: TZPgCharactersetType;
end;
{$IFNDEF CHECK_CLIENT_CODE_PAGE}
const

pg_CS_Table: array [0..47] of pg_CS =
(
  (name:'SQL_ASCII'; code: csSQL_ASCII),
  (name:'EUC_JP'; code: csEUC_JP),
  (name:'EUC_CN'; code: csEUC_CN),
  (name:'EUC_KR'; code: csEUC_KR),
  (name:'EUC_TW'; code: csEUC_TW),
  (name:'EUC_JIS_2004'; code: csEUC_JIS_2004),
  (name:'UTF8'; code: csUTF8),
  (name:'MULE_INTERNAL'; code: csMULE_INTERNAL),
  (name:'LATIN1'; code: csLATIN1),
  (name:'LATIN2'; code: csLATIN2),
  (name:'LATIN3'; code: csLATIN3),
  (name:'LATIN4'; code: csLATIN4),
  (name:'LATIN5'; code: csLATIN5),
  (name:'LATIN6'; code: csLATIN6),
  (name:'LATIN7'; code: csLATIN7),
  (name:'LATIN8'; code: csLATIN8),
  (name:'LATIN9'; code: csLATIN9),
  (name:'LATIN10'; code: csLATIN10),
  (name:'WIN1256'; code: csWIN1256),
  (name:'WIN1258'; code: csWIN1258),     { since 8.1 }
  (name:'WIN866'; code: csWIN866),     { since 8.1 }
  (name:'WIN874'; code: csWIN874),
  (name:'KOI8R'; code: csKOI8R),
  (name:'WIN1251'; code: csWIN1251),
  (name:'WIN1252'; code: csWIN1252),
  (name:'ISO_8859_5'; code: csISO_8859_5),
  (name:'ISO_8859_6'; code: csISO_8859_6),
  (name:'ISO_8859_7'; code: csISO_8859_7),
  (name:'ISO_8859_8'; code: csISO_8859_8),
  (name:'WIN1250'; code: csWIN1250),
  (name:'WIN1253'; code: csWIN1253),
  (name:'WIN1254'; code: csWIN1254),
  (name:'WIN1255'; code: csWIN1255),
  (name:'WIN1257'; code: csWIN1257),
  (name:'KOI8U'; code: csKOI8U),
  (name:'SJIS'; code: csSJIS),
  (name:'BIG5'; code: csBIG5),
  (name:'GBK'; code: csGBK),
  (name:'UHC'; code: csUHC),
  (name:'WIN1250'; code: csWIN1250),
  (name:'GB18030'; code: csGB18030),
  (name:'JOHAB'; code: csJOHAB),
  (name:'SHIFT_JIS_2004'; code: csSHIFT_JIS_2004),
  (name:'UNICODE'; code: csUNICODE_PODBC),
  (name:'TCVN'; code: csTCVN),
  (name:'ALT'; code: csALT),
  (name:'WIN'; code: csWIN),
  (name:'OTHER'; code: csOTHER)
);

{$ENDIF}
{**
   Return ZSQLType from PostgreSQL type name
   @param Connection a connection to PostgreSQL
   @param The TypeName is PostgreSQL type name
   @return The ZSQLType type
}
function PostgreSQLToSQLType(Connection: IZPostgreSQLConnection;
  TypeName: string): TZSQLType;
begin
  TypeName := LowerCase(TypeName);
  if (TypeName = 'interval') or (TypeName = 'char')
    or (TypeName = 'varchar') or (TypeName = 'bit') or (TypeName = 'varbit') then
    {$IFDEF CHECK_CLIENT_CODE_PAGE}  //EgonHugeist: Highest Priority Client_Character_set!!!!
    if Connection.GetClientCodePageInformations^.Encoding in [ceUTF8, ceUTF16{$IFNDEF MSWINDOWS}, ceUTF32{$ENDIF}] then
      Result := stUnicodeString
    else
      Result := stString
    {$ELSE}
    Result := stString
    {$ENDIF}
  else if TypeName = 'text' then
    Result := stAsciiStream
  else if TypeName = 'oid' then
  begin
    if Connection.IsOidAsBlob() then
      Result := stBinaryStream
    else
      Result := stInteger;
  end
  else if TypeName = 'name' then
    {$IFDEF CHECK_CLIENT_CODE_PAGE}  //EgonHugeist: Highest Priority Client_Character_set!!!!
    if Connection.GetClientCodePageInformations^.Encoding in [ceUTF8, ceUTF16{$IFNDEF MSWINDOWS}, ceUTF32{$ENDIF}] then
      Result := stUnicodeString
    else
      Result := stString
    {$ELSE}
    Result := stString
    {$ENDIF}
  else if TypeName = 'enum' then
    Result := stString
  else if TypeName = 'cidr' then
    Result := stString
  else if TypeName = 'inet' then
    Result := stString
  else if TypeName = 'macaddr' then
    Result := stString
  else if TypeName = 'int2' then
    Result := stShort
  else if TypeName = 'int4' then
    Result := stInteger
  else if TypeName = 'int8' then
    Result := stLong
  else if TypeName = 'float4' then
    Result := stFloat
  else if (TypeName = 'float8') or (TypeName = 'decimal')
    or (TypeName = 'numeric') then
    Result := stDouble
  else if TypeName = 'money' then
    Result := stBigDecimal
  else if TypeName = 'bool' then
    Result := stBoolean
  else if TypeName = 'date' then
    Result := stDate
  else if TypeName = 'time' then
    Result := stTime
  else if (TypeName = 'datetime') or (TypeName = 'timestamp')
    or (TypeName = 'timestamptz') or (TypeName = 'abstime') then
    Result := stTimestamp
  else if TypeName = 'regproc' then
    Result := stString
  else if TypeName = 'bytea' then
  begin
    if Connection.IsOidAsBlob then
      Result := stBytes
    else
      Result := stBinaryStream;
  end
  else if TypeName = 'bpchar' then
    Result := stString
  else if (TypeName = 'int2vector') or (TypeName = 'oidvector')
    or (TypeName = '_aclitem') then
    Result := stAsciiStream
  else if (TypeName <> '') and (TypeName[1] = '_') then // ARRAY TYPES
    Result := stAsciiStream
  else
    Result := stUnknown;

  {$IFDEF CHECK_CLIENT_CODE_PAGE}
  {$IFNDEF FPC}
  if Connection.GetClientCodePageInformations^.Encoding in [ceUTF8, ceUTF16{$IFNDEF MSWINDOWS}, ceUTF32{$ENDIF}] then
    if Result = stAsciiStream then
      Result := {$IFNDEF VER150BELOW}stUnicodeStream{$ELSE}stAsciiStream{$ENDIF}; //Delphi 7 does not support WideMemos
  {$ENDIF}
  {$ELSE}
  if Connection.GetCharactersetCode = csUTF8 then  //whats with csUNICODE_PODBC ??
    case Result of
      stString: Result := {$IFDEF FPC}stString{$ELSE}stUnicodeString{$ENDIF};
      stAsciiStream: Result := stUnicodeStream;
    end;
  {$ENDIF}
end;

{**
   Another version of PostgreSQLToSQLType()
     - comparing integer should be faster than AnsiString.
   Return ZSQLType from PostgreSQL type name
   @param Connection a connection to PostgreSQL
   @param TypeOid is PostgreSQL type OID
   @return The ZSQLType type
}
function PostgreSQLToSQLType(Connection: IZPostgreSQLConnection;
  TypeOid: Integer): TZSQLType; overload;
begin
  case TypeOid of
    1186,18,1043:  { interval/char/varchar }
      {$IFDEF CHECK_CLIENT_CODE_PAGE}  //EgonHugeist: Highest Priority Client_Character_set!!!!
      if Connection.GetClientCodePageInformations^.Encoding in [ceUTF8, ceUTF16{$IFNDEF MSWINDOWS}, ceUTF32{$ENDIF}] then
        Result := stUnicodeString
      else
        Result := stString;
      {$ELSE}
      Result := stString;
      {$ENDIF}
    25: Result := stAsciiStream; { text }
    26: { oid }
      begin
        if Connection.IsOidAsBlob() then
          Result := stBinaryStream
        else
          Result := stInteger;
      end;
    19: { name }
      {$IFDEF CHECK_CLIENT_CODE_PAGE}  //EgonHugeist: Highest Priority Client_Character_set!!!!
      if ( Connection.GetClientCodePageInformations^.Encoding in [ceUTF8, ceUTF16{$IFNDEF MSWINDOWS}, ceUTF32{$ENDIF}] ) then
        Result := stUnicodeString
      else
        Result := stString;
      {$ELSE}
      Result := stString;
      {$ENDIF}
    21: Result := stShort; { int2 }
    23: Result := stInteger; { int4 }
    20: Result := stLong; { int8 }
    650: Result := stString; { cidr }
    869: Result := stString; { inet }
    829: Result := stString; { macaddr }
    700: Result := stFloat; { float4 }
    701,1700: Result := stDouble; { float8/numeric. no 'decimal' any more }
    790: Result := stBigDecimal; { money }
    16: Result := stBoolean; { bool }
    1082: Result := stDate; { date }
    1083: Result := stTime; { time }
    1114,1184,702: Result := stTimestamp; { timestamp,timestamptz/abstime. no 'datetime' any more}
    1560,1562: Result := stString; {bit/ bit varying string}
    24: Result := stString; { regproc }
    17: { bytea }
      begin
        if Connection.IsOidAsBlob then
          Result := stBytes
        else
          Result := stBinaryStream;
      end;
    1042: Result := stString; { bpchar }
    22,30: Result := stAsciiStream; { int2vector/oidvector. no '_aclitem' }
    651, 1000..1028: Result := stAsciiStream;
    else
      Result := stUnknown;
  end;

  {$IFDEF CHECK_CLIENT_CODE_PAGE}  //EgonHugeist: Highest Priority Client_Character_set!!!!
  if Connection.GetClientCodePageInformations^.Encoding in [ceUTF8, ceUTF16{$IFNDEF MSWINDOWS}, ceUTF32{$ENDIF}] then
    if Result = stAsciiStream then
      Result := {$IFNDEF VER150BELOW}stUnicodeStream{$ELSE}stAsciiStream{$ENDIF}; //Delphi 7 does not support WideMemos
  {$ELSE}
  if Connection.GetCharactersetCode = csUTF8 then  //whats with csUNICODE_PODBC ??
    case Result of
      stString: Result := {$IFDEF FPC}stString{$ELSE}stUnicodeString{$ENDIF};
      stAsciiStream: Result := stUnicodeStream;
    end;
  {$ENDIF}

end;

{**
  Indicate what field type is a number (integer, float and etc.)
  @param  the SQLType field type value
  @result true if field type number
}
function IsNumber(Value: TZSQLType): Boolean;
begin
  Result := Value in [stByte, stShort, stInteger, stLong,
    stFloat, stDouble, stBigDecimal];
end;

{**
  Converts an string into escape PostgreSQL format.
  @param Value a regular string.
  @return a string in PostgreSQL escape format.
}
function EncodeString(const Value: string): string;
var
  I: Integer;
  SrcLength, DestLength: Integer;
  SrcBuffer, DestBuffer: PChar;
begin
  SrcLength := Length(Value);
  SrcBuffer := PChar(Value);
  DestLength := 2;
  for I := 1 to SrcLength do
  begin
    if CharInSet(SrcBuffer^, [#0, '''', '\']) then
      Inc(DestLength, 4)
    else
      Inc(DestLength);
    Inc(SrcBuffer);
  end;

  SrcBuffer := PChar(Value);
  SetLength(Result, DestLength);
  DestBuffer := PChar(Result);
  DestBuffer^ := '''';
  Inc(DestBuffer);

  for I := 1 to SrcLength do
  begin
    if CharInSet(SrcBuffer^, [#0, '''', '\']) then
    begin
      DestBuffer[0] := '\';
      DestBuffer[1] := Char(Ord('0') + (Byte(SrcBuffer^) shr 6));
      DestBuffer[2] := Char(Ord('0') + ((Byte(SrcBuffer^) shr 3) and $07));
      DestBuffer[3] := Char(Ord('0') + (Byte(SrcBuffer^) and $07));
      Inc(DestBuffer, 4);
    end
    else
    begin
      DestBuffer^ := SrcBuffer^;
      Inc(DestBuffer);
    end;
    Inc(SrcBuffer);
  end;
  {$IFNDEF CHECK_CLIENT_CODE_PAGE}
  DestBuffer^ := '''';
  {$ENDIF}
end;

{**
  Determine the character code in terms of enumerated number.
  @param InputString the input string.
  @return the character code in terms of enumerated number.
}
{$IFNDEF CHECK_CLIENT_CODE_PAGE}
function pg_CS_code(const InputString: string): TZPgCharactersetType;
var
  i,len: integer;
begin
  Result := csOTHER;

  i := 0;
  while pg_CS_Table[i].code <> csOTHER do
  begin
    if UpperCase(InputString) = UpperCase(pg_CS_Table[i].name) then
    begin
        Result := pg_CS_Table[i].code;
        break;
    end;
    Inc(i);
  end;

  if Result = csOTHER then { No exact match. Look for the closest match. }
  begin
    i := 0;
    len := 0;
    while pg_CS_Table[i].code <> csOTHER do
    begin
      if Pos(pg_CS_Table[i].name, InputString) > 0 then
      begin
        if Length(pg_CS_Table[i].name) >= len then
        begin
          len := Length(pg_CS_Table[i].name);
          Result := pg_CS_Table[i].code;
        end;
      end;
      Inc(i);
    end;
  end;
end;
{$ENDIF}

function pg_CS_stat(stat: integer; character: integer;
        CharactersetCode: TZPgCharactersetType): integer;
begin
  if character = 0 then
    stat := 0;

  case CharactersetCode of
    csUTF8, csUNICODE_PODBC:
      begin
	if (stat < 2) and (character >= $80) then
		begin
			if character >= $fc then
				stat := 6
			else if character >= $f8 then
				stat := 5
			else if character >= $f0 then
				stat := 4
			else if character >= $e0 then
				stat := 3
			else if character >= $c0 then
				stat := 2;
		end
		else if (stat > 2) and (character > $7f) then
			Dec(stat)
		else
			stat := 0;
      end;
{ Shift-JIS Support. }
    csSJIS:
      begin
		if (stat < 2)
		  and (character > $80)
		  and not ((character > $9f) and (character < $e0)) then
			stat := 2
		else if stat = 2 then
			stat := 1
		else
			stat := 0;
      end;
{ Chinese Big5 Support. }
    csBIG5:
      begin
		if (stat < 2) and (character > $A0) then
			stat := 2
		else if stat = 2 then
			stat := 1
		else
			stat := 0;
      end;
{ Chinese GBK Support. }
    csGBK:
      begin
		if (stat < 2) and (character > $7F) then
			stat := 2
		else if stat = 2 then
			stat := 1
		else
			stat := 0;
      end;

{ Korian UHC Support. }
    csUHC:
      begin
		if (stat < 2) and (character > $7F) then
			stat := 2
		else if stat = 2 then
			stat := 1
		else
			stat := 0;
      end;

{ EUC_JP Support }
    csEUC_JP:
      begin
		if (stat < 3) and (character = $8f) then { JIS X 0212 }
			stat := 3
		else
		if (stat <> 2)
		  and ((character = $8e) or
			(character > $a0)) then { Half Katakana HighByte & Kanji HighByte }
			stat := 2
		else if stat = 2 then
			stat := 1
		else
			stat := 0;
      end;

{ EUC_CN, EUC_KR, JOHAB Support }
    csEUC_CN, csEUC_KR, csJOHAB:
      begin
		if (stat < 2) and (character > $a0) then
			stat := 2
		else if stat = 2 then
			stat := 1
		else
			stat := 0;
      end;
    csEUC_TW:
      begin
		if (stat < 4) and (character = $8e) then
			stat := 4
		else if (stat = 4) and (character > $a0) then
			stat := 3
		else if ((stat = 3) or (stat < 2)) and (character > $a0) then
			stat := 2
		else if stat = 2 then
			stat := 1
		else
			stat := 0;
      end;
			{ Chinese GB18030 support.Added by Bill Huang <bhuang@redhat.com> <bill_huanghb@ybb.ne.jp> }
    csGB18030:
      begin
		if (stat < 2) and (character > $80) then
			stat := 2
		else if stat = 2 then
		begin
			if (character >= $30) and (character <= $39) then
				stat := 3
			else
				stat := 1;
		end
		else if stat = 3 then
		begin
			if (character >= $30) and (character <= $39) then
				stat := 1
			else
				stat := 3;
		end
		else
			stat := 0;
      end;
    else
		stat := 0;
  end;
  Result := stat;
end;

{**
  Encode string which probably consists of multi-byte characters.
  Characters ' (apostraphy), low value (value zero), and \ (back slash) are encoded.
  Since we have noticed that back slash is the second byte of some BIG5 characters
    (each of them is two bytes in length), we need a characterset aware encoding function.
  @param CharactersetCode the characterset in terms of enumerate code.
  @param Value the regular string.
  @return the encoded string.
}
function EncodeString(CharactersetCode: TZPgCharactersetType; const Value: {$IFDEF CHECK_CLIENT_CODE_PAGE}AnsiString{$ELSE}string{$ENDIF}): string;
var
  I, LastState: Integer;
  SrcLength, DestLength: Integer;
  SrcBuffer, DestBuffer: {$IFDEF CHECK_CLIENT_CODE_PAGE}PAnsiChar{$ELSE}PChar{$ENDIF};
 begin
  SrcLength := Length(Value);
  SrcBuffer := PChar(Value);
  DestLength := 2;
  LastState := 0;
  for I := 1 to SrcLength do
  begin
    LastState := pg_CS_stat(LastState,integer(SrcBuffer^),CharactersetCode);
    if CharInSet(SrcBuffer^, [#0, '''']) or ((SrcBuffer^ = '\') and (LastState = 0)) then
      Inc(DestLength, 4)
    else
      Inc(DestLength);
    Inc(SrcBuffer);
  end;

  SrcBuffer := {$IFDEF CHECK_CLIENT_CODE_PAGE}PAnsiChar{$ELSE}PChar{$ENDIF}(Value);
  SetLength(Result, DestLength);
  DestBuffer := {$IFDEF CHECK_CLIENT_CODE_PAGE}PAnsiChar{$ELSE}PChar{$ENDIF}(Result);
  DestBuffer^ := '''';
  Inc(DestBuffer);

  LastState := 0;
  for I := 1 to SrcLength do
  begin
    LastState := pg_CS_stat(LastState,integer(SrcBuffer^),CharactersetCode);
    if CharInSet(SrcBuffer^, [#0, '''']) or ((SrcBuffer^ = '\') and (LastState = 0)) then
    begin
      DestBuffer[0] := '\';
      DestBuffer[1] := {$IFDEF CHECK_CLIENT_CODE_PAGE}AnsiChar{$ELSE}Char{$ENDIF}(Ord('0') + (Byte(SrcBuffer^) shr 6));
      DestBuffer[2] := {$IFDEF CHECK_CLIENT_CODE_PAGE}AnsiChar{$ELSE}Char{$ENDIF}(Ord('0') + ((Byte(SrcBuffer^) shr 3) and $07));
      DestBuffer[3] := {$IFDEF CHECK_CLIENT_CODE_PAGE}AnsiChar{$ELSE}Char{$ENDIF}(Ord('0') + (Byte(SrcBuffer^) and $07));
      Inc(DestBuffer, 4);
    end
    else
    begin
      DestBuffer^ := SrcBuffer^;
      Inc(DestBuffer);
    end;
    Inc(SrcBuffer);
  end;
  DestBuffer^ := '''';
end;


{**
  add by Perger -> based on SourceForge:
  [ 1520587 ] Fix for 1484704: bytea corrupted on post when not using utf8,
  file: 1484704.patch

  Converts a binary string into escape PostgreSQL format.
  @param Value a binary stream.
  @return a string in PostgreSQL binary string escape format.
}
{$IFDEF CHECK_CLIENT_CODE_PAGE}
function EncodeBinaryString(const Value: AnsiString): AnsiString;
{$ELSE}
function EncodeBinaryString(const Value: string): string;
{$ENDIF}
var
  I: Integer;
  SrcLength, DestLength: Integer;
  SrcBuffer, DestBuffer: PAnsiChar;
begin
  SrcLength := Length(Value);
  SrcBuffer := PAnsiChar(Value);
  DestLength := 2;
  for I := 1 to SrcLength do
  begin
    if (Byte(SrcBuffer^) < 32) or (Byte(SrcBuffer^) > 126)
    or CharInSet(SrcBuffer^, ['''', '\']) then
      Inc(DestLength, 5)
    else
      Inc(DestLength);
    Inc(SrcBuffer);
  end;

  SrcBuffer := PAnsiChar(Value);
  SetLength(Result, DestLength);
  DestBuffer := PAnsiChar(Result);
  DestBuffer^ := '''';
  Inc(DestBuffer);

  for I := 1 to SrcLength do
  begin
    if (Byte(SrcBuffer^) < 32) or (Byte(SrcBuffer^) > 126)
    or CharInSet(SrcBuffer^, ['''', '\']) then
    begin
      DestBuffer[0] := '\';
      DestBuffer[1] := '\';
      DestBuffer[2] := AnsiChar(Ord('0') + (Byte(SrcBuffer^) shr 6));
      DestBuffer[3] := AnsiChar(Ord('0') + ((Byte(SrcBuffer^) shr 3) and $07));
      DestBuffer[4] := AnsiChar(Ord('0') + (Byte(SrcBuffer^) and $07));
      Inc(DestBuffer, 5);
    end
    else
    begin
      DestBuffer^ := SrcBuffer^;
      Inc(DestBuffer);
    end;
    Inc(SrcBuffer);
  end;
  DestBuffer^ := '''';
end;

{**
  Converts an string from escape PostgreSQL format.
  @param Value a string in PostgreSQL escape format.
  @return a regular string.
}
function DecodeString(const Value: AnsiString): AnsiString;
var
  SrcLength, DestLength: Integer;
  SrcBuffer, DestBuffer: PAnsiChar;
begin
  SrcLength := Length(Value);
  SrcBuffer := PAnsiChar(Value);
  SetLength(Result, SrcLength);
  DestLength := 0;
  DestBuffer := PAnsiChar(Result);

  while SrcLength > 0 do
  begin
    if SrcBuffer^ = '\' then
    begin
      Inc(SrcBuffer);
      if CharInSet(SrcBuffer^, ['\', '''']) then
      begin
        DestBuffer^ := SrcBuffer^;
        Inc(SrcBuffer);
        Dec(SrcLength, 2);
      end
      else
      begin
        DestBuffer^ := AnsiChar(((Byte(SrcBuffer[0]) - Ord('0')) shl 6)
          or ((Byte(SrcBuffer[1]) - Ord('0')) shl 3)
          or ((Byte(SrcBuffer[2]) - Ord('0'))));
        Inc(SrcBuffer, 3);
        Dec(SrcLength, 4);
      end;
    end
    else
    begin
      DestBuffer^ := SrcBuffer^;
      Inc(SrcBuffer);
      Dec(SrcLength);
    end;
    Inc(DestBuffer);
    Inc(DestLength);
  end;
  SetLength(Result, DestLength);
end;

{**
  Checks for possible sql errors.
  @param Connection a reference to database connection to execute Rollback.
  @param PlainDriver a PostgreSQL plain driver.
  @param Handle a PostgreSQL connection reference.
  @param LogCategory a logging category.
  @param LogMessage a logging message.
  //FirmOS 22.02.06
  @param ResultHandle the Handle to the Result
}
procedure CheckPostgreSQLError(Connection: IZConnection;
  PlainDriver: IZPostgreSQLPlainDriver;
  Handle: PZPostgreSQLConnect; LogCategory: TZLoggingCategory;
  const LogMessage: string;
  ResultHandle: PZPostgreSQLResult);

var
   ErrorMessage: string;
//FirmOS
   StatusCode: string;
   ConnectionLost: boolean;
begin
  if Assigned(Handle) then
 {$IFDEF DELPHI12_UP}
    ErrorMessage := Trim(UTF8ToUnicodeString(StrPas(PlainDriver.GetErrorMessage(Handle))))
 {$ELSE}
    ErrorMessage := Trim(StrPas(PlainDriver.GetErrorMessage(Handle)))
 {$ENDIF}
  else
    ErrorMessage := '';
  if ErrorMessage <> '' then
  begin
    if Assigned(ResultHandle) then
    begin
{     StatusCode := Trim(StrPas(PlainDriver.GetResultErrorField(ResultHandle,PG_DIAG_SEVERITY)));
     StatusCode := Trim(StrPas(PlainDriver.GetResultErrorField(ResultHandle,PG_DIAG_MESSAGE_PRIMARY)));
     StatusCode := Trim(StrPas(PlainDriver.GetResultErrorField(ResultHandle,PG_DIAG_MESSAGE_DETAIL)));
     StatusCode := Trim(StrPas(PlainDriver.GetResultErrorField(ResultHandle,PG_DIAG_MESSAGE_HINT)));
     StatusCode := Trim(StrPas(PlainDriver.GetResultErrorField(ResultHandle,PG_DIAG_STATEMENT_POSITION)));
     StatusCode := Trim(StrPas(PlainDriver.GetResultErrorField(ResultHandle,PG_DIAG_INTERNAL_POSITION)));
     StatusCode := Trim(StrPas(PlainDriver.GetResultErrorField(ResultHandle,PG_DIAG_INTERNAL_QUERY)));
     StatusCode := Trim(StrPas(PlainDriver.GetResultErrorField(ResultHandle,PG_DIAG_CONTEXT)));
     StatusCode := Trim(StrPas(PlainDriver.GetResultErrorField(ResultHandle,PG_DIAG_SOURCE_FILE)));
     StatusCode := Trim(StrPas(PlainDriver.GetResultErrorField(ResultHandle,PG_DIAG_SOURCE_LINE)));
     StatusCode := Trim(StrPas(PlainDriver.GetResultErrorField(ResultHandle,PG_DIAG_SOURCE_FUNCTION)));
}     
     StatusCode := Trim(StrPas(PlainDriver.GetResultErrorField(ResultHandle,PG_DIAG_SQLSTATE)));
    end
    else
    begin
     StatusCode:='';
    end;
  end;



  if ErrorMessage <> '' then
  begin
    ConnectionLost := (PlainDriver.GetStatus(Handle) = CONNECTION_BAD);

    if Assigned(Connection) and Connection.GetAutoCommit
                            and not ConnectionLost then
      Connection.Rollback;

    DriverManager.LogError(LogCategory, PlainDriver.GetProtocol, LogMessage,
      0, ErrorMessage);

    if ResultHandle <> nil then PlainDriver.Clear(ResultHandle);

    raise EZSQLException.CreateWithStatus(StatusCode,Format(SSQLError1, [ErrorMessage]));
  end;
end;

{**
   Resolve problem with minor version in PostgreSql bettas
   @param Value a minor version string like "4betta2"
   @return a miror version number
}
function GetMinorVersion(const Value: string): Word;
var
  I: integer;
  Temp: string;
begin
  Temp := '';
  for I := 1 to Length(Value) do
    if CharInSet(Value[I], ['0'..'9']) then
      Temp := Temp + Value[I]
    else
      Break;
  Result := StrToIntDef(Temp, 0);
end;

end.
