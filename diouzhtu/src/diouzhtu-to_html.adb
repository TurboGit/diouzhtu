------------------------------------------------------------------------------
--                               Diouzhtu                                   --
--                                                                          --
--                           Copyright (C) 2007                             --
--                            Olivier Ramonat                               --
--                                                                          --
--  This library is free software; you can redistribute it and/or modify    --
--  it under the terms of the GNU General Public License as published by    --
--  the Free Software Foundation; either version 2 of the License, or (at   --
--  your option) any later version.                                         --
--                                                                          --
--  This library is distributed in the hope that it will be useful, but     --
--  WITHOUT ANY WARRANTY; without even the implied warranty of              --
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU       --
--  General Public License for more details.                                --
--                                                                          --
--  You should have received a copy of the GNU General Public License       --
--  along with this library; if not, write to the Free Software Foundation, --
--  Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.       --
------------------------------------------------------------------------------

with Ada.Strings.Unbounded;
with Ada.Strings.Fixed;
with Ada.Strings.Maps;
with Ada.Characters.Handling;
with Ada.Text_IO;

with Diouzhtu.Block;
with Diouzhtu.Code;
with Diouzhtu.Inline;

package body Diouzhtu.To_HTML is

   use Ada;
   use Ada.Text_IO;
   use Ada.Strings.Unbounded;

   function CR_Delete (S : String) return String;
   --  Delete all CR characters

   function Web_Escape (S : in String) return String;
   --  Escape web characters

   ---------------
   -- CR_Delete --
   ---------------

   function CR_Delete (S : String) return String is
      CR : constant String (1 .. 1) := (1 => ASCII.CR);
   begin
      return Strings.Fixed.Trim
        (Strings.Fixed.Translate
           (S, Strings.Maps.To_Mapping
              (From => CR, To   => " ")),
         Strings.Right);
   end CR_Delete;

   ------------------
   -- Text_To_HTML --
   ------------------

   function Text_To_HTML (Wiki : Wiki_Information; S : String) return String is
      Text : constant String := CR_Delete (S);

      Content       : Unbounded_String := Null_Unbounded_String;
      Result        : Unbounded_String := Null_Unbounded_String;
      Last          : Positive := S'First;

      In_Code_Block  : Boolean := False;
      End_Code_Block : constant String := "end code.";

      procedure Block_To_HTML;
      --  Parse a block content

      -------------------
      -- Block_To_HTML --
      -------------------

      procedure Block_To_HTML is
         Block_Content : constant String := To_String (Content);
      begin

         if In_Code_Block then

            --  Search for end tag

            if Block_Content'Length >= End_Code_Block'Length
              and then
                Block_Content
                  (Block_Content'First ..
                         Block_Content'First +
                           End_Code_Block'Length - 1)
                      = End_Code_Block then
               Append (Result, Code.End_Code);
               In_Code_Block := False;
            else
               Append (Result, ASCII.Lf & ASCII.Lf & Block_Content);
            end if;

         else
            declare
               Code_Content : constant String :=
                                Code.Begin_Code (Block_Content);
            begin
               if Code_Content /= "" then
                  In_Code_Block := True;
                  Append (Result, Code_Content);
               else
                  Append
                    (Result,
                     Parse
                       (Wiki, Block_Level, To_String (Content)));
               end if;
            end;
         end if;
      end Block_To_HTML;

   begin

      for K in S'Range loop
         if Text (K) = ASCII.Lf then
            if Last < K - 1 then
               if Content /= Null_Unbounded_String then
                  Append (Content, ASCII.Lf);
               end if;
               Append (Content, Web_Escape (Text (Last .. K - 1)));
            else
               if Content /= Null_Unbounded_String then
                  Block_To_HTML;
                  Content := Null_Unbounded_String;
               end if;
            end if;
            Last := K + 1;
         end if;
      end loop;

      if Last < Text'Last then
         Append (Content, Web_Escape (Text (Last .. S'Last)));
      end if;

      if Content /= Null_Unbounded_String then
         Block_To_HTML;
      end if;

      return To_String (Result);
   end Text_To_HTML;

   -------------
   -- To_HTML --
   -------------

   function To_HTML
     (Wiki : Wiki_Information; Filename : String) return String
   is
      Diouzhtu_File : File_Type;
      Result        : Unbounded_String := Null_Unbounded_String;
   begin

      Open (File => Diouzhtu_File,
            Mode => In_File,
            Name => To_String (Wiki.Text_Directory) & "/" & Filename);

      while not End_Of_File (Diouzhtu_File) loop
         Append (Result, Get_Line (Diouzhtu_File));
         Append (Result, ASCII.Lf);
      end loop;

      Close (Diouzhtu_File);

      return Text_To_HTML (Wiki, To_String (Result));
   exception
      when others =>
         if Is_Open (Diouzhtu_File) then
            Close (Diouzhtu_File);
         end if;
         return "";
   end To_HTML;

   ----------------
   -- Web_Escape --
   ----------------

   function Web_Escape (S : in String) return String is

      Result : Unbounded_String;
      Last   : Integer := S'First;

      procedure Append_To_Result
        (Str : in String; From : in Integer; To : in Integer);
      --  Append S (From .. To) to Result if not empty concatenated with Str
      --  and update Last.

      ----------------------
      -- Append_To_Result --
      ----------------------

      procedure Append_To_Result
        (Str : in String; From : in Integer; To : in Integer) is
      begin
         if From <= To then
            Append (Result, S (From .. To) & Str);
         else
            Append (Result, Str);
         end if;

         Last := To + 2;
      end Append_To_Result;

      To_Skip : Natural := 0;
   begin
      for I in S'Range loop
         if To_Skip /= 0 then
            To_Skip := To_Skip - 1;
         else
            case S (I) is
               when '&'    =>
                  for K in I + 1 .. S'Last loop
                     if not Ada.Characters.Handling.Is_Letter (S (K)) then
                        if S (K) /= ';' then
                           Append_To_Result ("&amp;", Last, I - 1);
                        else
                           --  Allow xml entities &copy; &reg; &quot; ...
                           To_Skip := K - I;
                        end if;
                        exit;
                     end if;
                  end loop;
               when '>'    => Append_To_Result ("&gt;", Last, I - 1);
               when '<'    => Append_To_Result ("&lt;", Last, I - 1);
               --  when '"'    => Append_To_Result ("&quot;", Last, I - 1);
               when others => null;
            end case;
         end if;
      end loop;

      if Last <= S'Last then
         Append (Result, S (Last .. S'Last));
      end if;

      return To_String (Result);
   end Web_Escape;

begin
   Diouzhtu.Block.Register;
   Diouzhtu.Inline.Register;
end Diouzhtu.To_HTML;
