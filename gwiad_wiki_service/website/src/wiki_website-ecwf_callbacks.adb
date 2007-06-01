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

with GNAT.Calendar.Time_IO;

with Ada.Strings.Unbounded;

with Wiki_Website.Config;
with Wiki_Website.Service;
with Wiki_Website.Template_Defs.Top;
with Wiki_Website.Template_Defs.Bottom;
with Wiki_Website.Template_Defs.Block_Menu;
with Wiki_Website.Template_Defs.Block_View;

with Ada.Directories;
with Ada.Text_IO;

with Gwiad.OS;
with Gwiad.Services.Register;

with Wiki_Interface;

package body Wiki_Website.ECWF_Callbacks is

   use Ada;
   use Ada.Strings.Unbounded;
   use Ada.Text_IO;

   use Wiki_Interface;

   use Wiki_Website;
   use Wiki_Website.Config;

   ----------
   -- Menu --
   ----------

   procedure Menu
     (Request      : in     Status.Data;
      Context      : access AWS.Services.ECWF.Context.Object;
      Translations : in out Templates.Translate_Set)
   is
      pragma Unreferenced (Context);
      pragma Warnings (Off);
      use AWS.Status;
      use Ada.Directories;

      Get_URI        : constant String := URI (Request);
      Name           : constant Wiki_Name := Get_Wiki_Name (Request);
      Web_Root       : constant String := Get_Wiki_Web_Root (Name);
      HTML_Root      : constant String
        := Current_Directory & Gwiad.OS.Directory_Separator
          & Wiki_HTML_Dir (Name);
      HTML_Directory : constant String
        := Current_Directory & Gwiad.OS.Directory_Separator
          & Containing_Directory (Wiki_HTML_Dir (Name)
                                  & Gwiad.OS.Directory_Separator
                                  & Get_Directory (Web_Root, Get_URI));

      procedure Menu
        (From : in String; Filenames : in out Templates.Vector_Tag);
      --  Creates the menu

      ----------
      -- Menu --
      ----------

      procedure Menu
        (From : in String; Filenames : in out Templates.Vector_Tag) is
         S : Search_Type;
         D : Directory_Entry_Type;
         use type Templates.Vector_Tag;
      begin
         Filenames := Filenames & Template_Defs.Block_Menu.Set.SET_BEGIN_BLOCK;
         Start_Search (Search    => S,
                       Directory => From,
                       Pattern   => "*",
                       Filter    => (Directory     => True,
                                     Ordinary_File => True,
                                     Special_File  => False));
         while More_Entries (S) loop
            Get_Next_Entry (S, D);
            declare
               Name      : constant String := Simple_Name (D);
               Full_Name : constant String := Directories.Full_Name (D);
            begin
               if Name /= "." and Name /= ".." then
                  --  Now read the config file if any

                  if Kind (D) = Directory  then
                     Filenames := Filenames
                       & (Full_Name (Full_Name'First + HTML_Root'Length
                                   .. Full_Name'Last) & '/');
                     if Full_Name'Length <= HTML_Directory'Length
                       and then
                         Full_Name = HTML_Directory
                           (HTML_Directory'First ..
                                  HTML_Directory'First + Full_Name'Length - 1)
                     then
                        Menu (Full_Name, Filenames);
                     else

                        Ada.Text_IO.Put_Line
                          (Full_Name & " /= " & HTML_Directory
                           & " ??? " & Current_Directory);
                     end if;
                  else
                     Filenames := Filenames
                       & Full_Name (Full_Name'First + HTML_Root'Length
                                    .. Full_Name'Last);

                  end if;
               end if;
            end;
         end loop;
         Filenames := Filenames & Template_Defs.Block_Menu.Set.SET_END_BLOCK;
      end Menu;


      Filenames : Templates.Vector_Tag;
   begin

      Templates.Insert
        (Translations,
         Templates.Assoc (Template_Defs.Top.WIKI_NAME, String (Name)));


      Menu (Wiki_HTML_Dir (Name), Filenames);

      Templates.Insert
        (Translations,
         Templates.Assoc (Variable => Template_Defs.Block_Menu.NAME_V,
                          Value    => Filenames));
   end Menu;

   -------------------
   -- Menu_Template --
   -------------------

   function Menu_Template (Request : in Status.Data) return String is
      Name : constant Wiki_Name := Get_Wiki_Name (Request);
   begin
      return Wiki_Root (Name) & Gwiad.OS.Directory_Separator
        & Template_Defs.Block_Menu.Template;
   end Menu_Template;

   ----------
   -- View --
   ----------

   procedure View
     (Request      : in     Status.Data;
      Context      : access AWS.Services.ECWF.Context.Object;
      Translations : in out Templates.Translate_Set)
   is
      pragma Unreferenced (Context);
      use AWS.Status;
      use Ada.Directories;

      Get_URI       : constant String := URI (Request);
      Name          : constant Wiki_Name := Get_Wiki_Name (Request);
      Web_Root      : constant String := Get_Wiki_Web_Root (Name);
      Filename      : constant String := Get_Filename (Web_Root, Get_URI);
      HTML_Filename : constant String :=
                        Wiki_HTML_Dir (Name)
                        & Gwiad.OS.Directory_Separator & Filename;
      HTML_Text     : Unbounded_String := Null_Unbounded_String;
      HTML_File     : File_Type;

   begin

      Templates.Insert
        (Translations,
         Templates.Assoc (Template_Defs.Top.WIKI_NAME, String (Name)));

      Templates.Insert
        (Translations,
         Templates.Assoc (Template_Defs.Block_View.FILENAME, Filename));

      if Exists (HTML_Filename) then
         if Kind (HTML_Filename) /= Ordinary_File then
            return;
         end if;

         Open (File => HTML_File,
               Mode => In_File,
               Name => HTML_Filename);

         while not End_Of_File (HTML_File) loop
            Append (HTML_Text, Get_Line (HTML_File));
            Append (HTML_Text, ASCII.LF);
         end loop;

         Close (HTML_File);

         Templates.Insert
           (Translations, Templates.Assoc
              (Template_Defs.Block_View.VIEW, HTML_Text));

      elsif Exists (Wiki_Text_Dir (Name) & "/" & Filename)
        and then Kind (Wiki_Text_Dir (Name)
                       & "/" & Filename) = Ordinary_File
      then

         if not Gwiad.Services.Register.Exists (Wiki_Service_Name) then
            Templates.Insert
              (Translations,
               Templates.Assoc ("ERROR", "<p>Service down</p>"));
         end if;

         declare
            Get_Service : GW_Service'Class := Service.Get (Name, Web_Root);
            New_HTML    : constant String  := HTML (Get_Service, Filename);
         begin
            Templates.Insert
              (Translations,
               Templates.Assoc (Template_Defs.Block_View.VIEW, New_HTML));

            Create_Path (Containing_Directory (HTML_Filename));

            Create (File => HTML_File,
                    Mode => Out_File,
                    Name => HTML_Filename);

            Put (HTML_File, New_HTML);

            Close (HTML_File);
         end;
      end if;

      if Exists (HTML_Filename) then
         Templates.Insert
           (Translations,
            Templates.Assoc (Template_Defs.Bottom.MODIFICATION_DATE,
              GNAT.Calendar.Time_IO.Image
                (Directories.Modification_Time
                   (Name => HTML_Filename), "%Y-%m-%d %T")));
      end if;
   end View;

   -------------------
   -- View_Template --
   -------------------

   function View_Template (Request : in Status.Data) return String is
      Name     : constant Wiki_Name := Get_Wiki_Name (Request);
   begin
      return Wiki_Root (Name) & Gwiad.OS.Directory_Separator
        & Template_Defs.Block_View.Template;
   end View_Template;

end Wiki_Website.ECWF_Callbacks;
