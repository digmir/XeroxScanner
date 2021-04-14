--[[
 * Copyright (c) 2020, digmir <dev@digmir.com>
 * 
 * This program is free software: you can use, redistribute, and/or modify
 * it under the terms of the GNU Affero General Public License, version 3
 * or later ("AGPL"), as published by the Free Software Foundation.
 * 
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.
 * 
 * You should have received a copy of the GNU Affero General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
]]

require "iuplua";
require "iupluaim";
require "lfs";
require "scanner";

local img = nil;
local imgcount = 0;
local thead_busy = false;

local device_ip = iup.text{ expand = "HORIZONTAL" , id = "device_ip" , value = "192.168.1.100" };
local save_path = iup.text{ expand = "HORIZONTAL" , id = "save_path" };
local btn_scan = iup.button{ title = "Scan" , rastersize = "x32" };
local btn_save = iup.button{ title = "Save" , rastersize = "x32" };
local papersize = iup.list{ "A4" , "B5" ; value="1" , dropdown = "YES" , visible_items = 5 , rastersize = "x32" };
local dpi = iup.list{ "100" , "150" , "200" , "300" , "400" , "600" ; value="1" , dropdown = "YES" , visible_items = 5 };
local color = iup.list{ "COLOR" , "GRAY" ; value="1" , dropdown = "YES" , visible_items = 5 };
local progs = iup.progressbar{ max = 100 , min = 0 , expand = "HORIZONTAL" , rastersize = "x1" };
local cs = iup.canvas{};
local csscrl = iup.scrollbox{ cs ; border = "YES" };

local WINDOWS = false;
local ENV_OS = os.getenv("OS");
if ENV_OS ~= nil and string.find( ENV_OS , "Windows" , 1 , true ) ~= nil then
    WINDOWS = true;
end

local inputctl = iup.vbox({
    iup.label{ title = "Device:" } ,
    iup.hbox({
        device_ip ,
        btn_scan
        ;
        margin = "0x0" ,
        alignment = "ACENTER"
    }) ,
    iup.hbox({
        iup.label{ title = " PaperSize: " } ,
        papersize ,
        iup.label{ title = "      DPI: " } ,
        dpi ,
        iup.label{ title = "      Color: " } ,
        color
        ;
        margin = "0x6" ,
        alignment = "ACENTER"
    })
});

local dlg = iup.dialog({
    iup.vbox({
        inputctl ,
        progs ,
        iup.label{ title = "Image:" } ,
        csscrl ,
        iup.hbox({
            iup.label{ expand = "HORIZONTAL" } ,
            btn_save
            ;
            margin = "0x1"
        }) ,
    })
    ;
    title   = "DocuPrint Scanner" ,
    margin  = "10x10" ,
    size    = "400x200" ,
});

function cs:action()
    cs:DrawBegin();
    local w, h = cs:DrawGetSize();
    cs.drawcolor = "255 255 255";
    cs.drawstyle = "FILL";
    cs:DrawRectangle( 0 , 0 , w , h );
    if img ~= nil then
        cs:DrawImage( img , 0 , 0 );
    end
    cs:DrawEnd();
end

function dlg:postmessage_cb( s , i , d , p )
    if s == "jobend" then
        if i ~= 0 then
            iup.Message( "Error" , "Scan failed!" );
        end
        
        thead_busy = false;
        inputctl.active = "YES";
        if imgcount > 0 then
            btn_save.active = "YES";
        end
        
        img = iup.LoadImage( "tmp/scan1.jpg" );
        if img ~= nil then
            cs.rastersize = img.width.."x"..img.height;
            iup.Redraw( cs , 0 );
            iup.Redraw( csscrl , 0 );
        end
    end
    return iup.DEFAULT;
end

function btn_scan:action()
    if thead_busy then
        return;
    end
    
    thead_busy = true;
    inputctl.active = "NO";
    btn_save.active = "NO";
    img = nil;
    imgcount = 0;
    if WINDOWS then
        os.execute("del /F /S /Q .\\tmp\\");
    else
        os.execute("rm -rf ./tmp/");
    end
    lfs.mkdir( "tmp" );
    
    local scn_thd = iup.thread{};
    function scn_thd:thread_cb()
        
        local param = {
            host = device_ip.value ,
            papersize = papersize.valuestring ,
            dpi = tonumber( dpi.valuestring ) ,
            color = color.valuestring ,
            filename = "tmp/scan" ,
            onprogress = function( no , p )
                imgcount = no;
                progs.value = p;
            end
        };
        
        local r1,r2 = pcall( scan , param );
        if not r1 or r1 ~= 0 then
            print(r2);
        end
        
        iup.PostMessage( dlg , "jobend" , r2 , 0 , nil );
        return iup.DEFAULT;
    end
    
    scn_thd.start = "YES";
end

function btn_save:action()
    local dlg = iup.filedlg{ dialogtype = "SAVE" }
    dlg:popup()
    if dlg.status == "1" then
        os.rename( "tmp/scan1.jpg" , dlg.value );
        btn_save.active = "NO";
        img = nil;
    end
end

dlg.size = "400x200";
dlg:show();
btn_save.active = "NO";

iup.MainLoop();
