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

local socket = require("socket");

function scan( param )
	local host = param.host;
	local port = param.port or 54921;
	local c = socket.tcp();
	c:settimeout( 60 );
	c:connect( host , port );
	
	local dpi = param.dpi or 300;
	local papersize = param.papersize or "A4";
	local color = param.color or "COLOR";
	local fileformat = param.fileformat or "JPEG";
	local filename = param.filename or "scan";
	local extname = "jpg";
	
	if color == "MONO" then
		fileformat = "RLENGTH";
		extname = "rle";
	end
	
	local IBEGIN = "\x1B";
	local IEND = "\x80";
	local LF = "\x0D\x0A";
	
	local read_head = false;
	
	local function scanner_req( sock , method , params )
		local data = IBEGIN.. method..LF;
		for k,v in pairs(params) do
			data = data..k.."="..v..LF;
		end
		data = data .. IEND;
		
		local res,status = sock:send(data);
		if res == nil then
			print(status);
			return false;
		end
		
		if not read_head then
			read_head = true;
			local res,status = sock:receive("*l");
			if res ~= "+OK 200" then
				print(res, status);
				return false;
			end
		end
		
		return true;
	end
	
	local function scanner_recv_info( sock )
		local res,status = sock:receive(3);
		local len = string.byte(res,1) * 0x100 + string.byte(res,2);
		local res,status = sock:receive(len);
		if res == nil then
			print(status);
			return nil;
		end
		
		local list = {};
		string.gsub(res, '[^,]+', function(s)
			table.insert(list, s)
		end);
		
		local ret = {
			dpi_x = list[1] ,
			dpi_y = list[2] ,
			scan_type = list[3] ,
			margin_x = list[4] ,
			margin_y = list[6] ,
			width = list[5] ,
			height = list[7] ,
		};
		
		return ret;
	end
	
	local function scanner_recv_image( sock , filename )
		local f = nil;
		local tp = 0;
		while true do
			local res,status = sock:receive(1);
			if res == nil then
				print(status);
				return false;
			end
			
			local code = string.byte(res,1);
			
			if code == 0x80 then
				break;
			end
			
			local res,status = sock:receive(2);
			if res == nil then
				print(status);
				return false;
			end
			
			local len = string.byte(res,2) * 0x100 + string.byte(res,1);
			local res,status = sock:receive(len);
			
			local no = string.byte(res,2) * 0x100 + string.byte(res,1);
			
			if code == 0x64 or code == 0x42 then
				if f == nil then
					f = io.open( filename..no.."."..extname , "wb" );
				end
				
				local p = string.byte(res, 5);
				p = math.min(100, p * 10);
				if tp ~= p then
					tp = p;
					if type( param.onprogress ) == "function" then
						param.onprogress( no , p );
					end
				end
				
				local res,status = sock:receive(2);
				local len = string.byte(res, 2) * 0x100
					+ string.byte(res, 1);
				
				if len == 0 then
					break;
				end
				
				local res,status = sock:receive(len);
				f:write(res);
				f:flush();
			elseif code == 0x82 then
				--finish
				if f ~= nil then
					f:close();
					f = nil;
				end
				if type( param.onprogress ) == "function" then
					param.onprogress( no , p );
				end
			end
		end
		
		if f ~= nil then
			f:close();
		end
		
		return true;
	end
	
	local ADF = 1;
	local MDF = 2;
	
	local COLORMODE = {
		COLOR = "CGRAY" ,
		GRAY = "GRAY64" ,
		MONO = "TEXT" ,
	};
	local PAPERMARGIN = {
		A4 = 12 ,
		B5 = 67 ,
	};
	local PAPERSIZE = {
		[100] = {
			A4 = {816,1145} ,
			B5 = {704,988} ,
		} ,
		[150] = {
			A4 = {1216,1718} ,
			B5 = {1040,1482} ,
		} ,
		[200] = {
			A4 = {1616,2291} ,
			B5 = {1392,1976} ,
		} ,
		[300] = {
			A4 = {2416,3437} ,
			B5 = {2080,2965} ,
		} ,
		[400] = {
			A4 = {3216,4582} ,
			B5 = {2784,3953} ,
		} ,
		[600] = {
			A4 = {4832,6874} ,
			B5 = {4160,5929} ,
		} ,
	}
	
	local conf = {
		R=dpi..","..dpi ,
		M=COLORMODE[color] ,
		D="SIN" ,
	}
	
	local res = scanner_req( c , "I" , conf );
	if not res then
		c:close();
		return 1;
	end
	
	local info = scanner_recv_info( c );
	if info == nil then
		c:close();
		return 1;
	end
	
	local offset_x = 0;
	local width = PAPERSIZE[dpi][papersize][1];
	local height = PAPERSIZE[dpi][papersize][2];
	
	if info.scan_type == ADF then
		offset_x = math.floor(PAPERMARGIN[papersize] * (dpi / 100));
		width = width + offset_x;
	end
	
	local res = scanner_req( c , "X" , {
		R=info.R ,
		M=conf.M ,
		C=fileformat ,
		J="MIN" ,
		B=50 ,
		N=50 ,
		A=offset_x..",0,"..width..",".. height,
		D=conf.D ,
		E=0 ,
		G=0 ,
	});
	if not res then
		c:close();
		return 1;
	end
	
	scanner_recv_image( c , filename );
	
	c:close();
	return 0;
end
