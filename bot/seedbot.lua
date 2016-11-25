package.path = package.path .. ';.luarocks/share/lua/5.2/?.lua'
  ..';.luarocks/share/lua/5.2/?/init.lua'
package.cpath = package.cpath .. ';.luarocks/lib/lua/5.2/?.so'

require("./bot/utils")

local f = assert(io.popen('/usr/bin/git describe --tags', 'r'))
VERSION = assert(f:read('*a'))
f:close()

-- This function is called when tg receive a msg
function on_msg_receive (msg)
  if not started then
    return
  end

  msg = backward_msg_format(msg)

  local receiver = get_receiver(msg)
  print(receiver)
  --vardump(msg)
  --vardump(msg)
  msg = pre_process_service_msg(msg)
  if msg_valid(msg) then
    msg = pre_process_msg(msg)
    if msg then
      match_plugins(msg)
      if redis:get("bot:markread") then
        if redis:get("bot:markread") == "on" then
          mark_read(receiver, ok_cb, false)
        end
      end
    end
  end
end

function ok_cb(extra, success, result)

end

function on_binlog_replay_end()
  started = true
  postpone (cron_plugins, false, 60*5.0)
  -- See plugins/isup.lua as an example for cron

  _config = load_config()

  -- load plugins
  plugins = {}
  load_plugins()
end

function msg_valid(msg)
  -- Don't process outgoing messages
  if msg.out then
    print('\27[36mNot valid: msg from us\27[39m')
    return false
  end

  -- Before bot was started
  if msg.date < os.time() - 5 then
    print('\27[36mNot valid: old msg\27[39m')
    return false
  end

  if msg.unread == 0 then
    print('\27[36mNot valid: readed\27[39m')
    return false
  end

  if not msg.to.id then
    print('\27[36mNot valid: To id not provided\27[39m')
    return false
  end

  if not msg.from.id then
    print('\27[36mNot valid: From id not provided\27[39m')
    return false
  end

  if msg.from.id == our_id then
    print('\27[36mNot valid: Msg from our id\27[39m')
    return false
  end

  if msg.to.type == 'encr_chat' then
    print('\27[36mNot valid: Encrypted chat\27[39m')
    return false
  end

  if msg.from.id == 777000 then
    --send_large_msg(*group id*, msg.text) *login code will be sent to GroupID*
    return false
  end

  return true
end

--
function pre_process_service_msg(msg)
   if msg.service then
      local action = msg.action or {type=""}
      -- Double ! to discriminate of normal actions
      msg.text = "!!tgservice " .. action.type

      -- wipe the data to allow the bot to read service messages
      if msg.out then
         msg.out = false
      end
      if msg.from.id == our_id then
         msg.from.id = 0
      end
   end
   return msg
end

-- Apply plugin.pre_process function
function pre_process_msg(msg)
  for name,plugin in pairs(plugins) do
    if plugin.pre_process and msg then
      print('Preprocess', name)
      msg = plugin.pre_process(msg)
    end
  end
  return msg
end

-- Go over enabled plugins patterns.
function match_plugins(msg)
  for name, plugin in pairs(plugins) do
    match_plugin(plugin, name, msg)
  end
end

-- Check if plugin is on _config.disabled_plugin_on_chat table
local function is_plugin_disabled_on_chat(plugin_name, receiver)
  local disabled_chats = _config.disabled_plugin_on_chat
  -- Table exists and chat has disabled plugins
  if disabled_chats and disabled_chats[receiver] then
    -- Checks if plugin is disabled on this chat
    for disabled_plugin,disabled in pairs(disabled_chats[receiver]) do
      if disabled_plugin == plugin_name and disabled then
        local warning = 'Plugin '..disabled_plugin..' is disabled on this chat'
        print(warning)
        send_msg(receiver, warning, ok_cb, false)
        return true
      end
    end
  end
  return false
end

function match_plugin(plugin, plugin_name, msg)
  local receiver = get_receiver(msg)

  -- Go over patterns. If one matches it's enough.
  for k, pattern in pairs(plugin.patterns) do
    local matches = match_pattern(pattern, msg.text)
    if matches then
      print("msg matches: ", pattern)

      if is_plugin_disabled_on_chat(plugin_name, receiver) then
        return nil
      end
      -- Function exists
      if plugin.run then
        -- If plugin is for privileged users only
        if not warns_user_not_allowed(plugin, msg) then
          local result = plugin.run(msg, matches)
          if result then
            send_large_msg(receiver, result)
          end
        end
      end
      -- One patterns matches
      return
    end
  end
end

-- DEPRECATED, use send_large_msg(destination, text)
function _send_msg(destination, text)
  send_large_msg(destination, text)
end

-- Save the content of _config to config.lua
function save_config( )
  serialize_to_file(_config, './data/config.lua')
  print ('saved config into ./data/config.lua')
end

-- Returns the config from config.lua file.
-- If file doesn't exist, create it.
function load_config( )
  local f = io.open('./data/config.lua', "r")
  -- If config.lua doesn't exist
  if not f then
    print ("Created new config file: data/config.lua")
    create_config()
  else
    f:close()
  end
  local config = loadfile ("./data/config.lua")()
  for v,user in pairs(config.sudo_users) do
    print("Sudo user: " .. user)
  end
  return config
end

-- Create a basic config.json file and saves it.
function create_config( )
  -- A simple config with basic plugins and ourselves as privileged user
  config = {
    enabled_plugins = {
	"admin",
    "onservice",
    "inrealm",
    "ingroup",
    "inpm",
    "banhammer",
    "stats",
    "anti_spam",
    "owners",
    "arabic_lock",
    "set",
    "get",
    "broadcast",
    "invite",
    "all",
    "leave_ban",
	"supergroup",
	"whitelist",
	"msg_checks"
    },
    sudo_users = {1207416,0,tonumber(our_id)},--Sudo users
    moderation = {data = 'data/moderation.json'},
    about_text = [[CclyberSource v1
An advanced administration bot based on TG-CLI written in Lua

https://github.com/SINGLECYBER/CyberSource

Admins
@SINGLECYBER

Special thanks to
awkward_potato
Siyanew
topkecleon
Vamptacus

Our channels
@SINGLECYBERCHANNEL [English]
@SINGLECYBERCHANNEL[persian]
]],
    help_text_realm = [[
<i>
<b>
CYBER SOURCE SUDO HELP
<b>
</i>

<b>
➲ creategroup [Name]
➤ ساخت یک گروه

➲ createrealm [Name]
➤ ساخت یک realm

➲ setname [Name]
➤تنظیم نام realm

➲ setabout [group|sgroup] [GroupID] [Text]
 ➤ تنظیم متن توضیحات یک گروه

➲ setrules [GroupID] [Text]
➤ تنظیم قوانین یک گروه

➲ lock [GroupID] [setting]
➤ قفل تنظیمات یک گروه

➲ unlock [GroupID] [setting]
➤ بازکردن تنظیمات یک گروه

➲ settings [group|sgroup] [GroupID]
➤ نمایش تنظیمات گروه یا سوپر گروه

➲ wholist
➤ لیست ممبر های یک گروه یا realm

➲ who
➤ دریافت یک فایل از اعضای گروه یا سوپرگروه

➲ type
➤ رفتن به type گروه

➲ kill chat [GroupID]
➤ حذف همه اعضا و پاک کردن  یک گروه

➲ kill realm [RealmID]
➤ حذف همه کاربران و پاک کردن realm

➲ addadmin [id|username]
➤ اضافه کردن یک مدیر

➲ removeadmin [id|username]
➤ تنزل یک کاربر از مدیر بودن

➲ list groups
➤ لیست همه گروه های ربات

➲ list realms
➤ لیست همه realm ها

➲ support
➤ دعوت یک کاربر به گروه پشتیبانی 

➲ -support
➤ا خراج یک کاربر از گروه پشتیبانی

➲ log
➤ نمایش فعلو انفعالات گروه

➲ broadcast [text]
!broadcast Hello 
➤ ارسال یک متن به همه گروه های ربات

➲ bc [group_id] [text]
bc 123456789 Hello !
➤ این دستور برای ارسال یک متن به یک گروه مشخصه [ایدی عددی گروه]

برای اجرا دستورات در این ورژن سورس از [ /#!]  در ابتدای دستورات استفاده کنید.
</b>

<i>➲ Devolopers : </i>
@SINGLECYBER
@MRJOOKER
]],
    help_text = [[➖➖➖➖➖➖➖ 
<i>
<b>
➲ CYBER SOURCE MODERATOR HELP
</b>
</i>
➖➖➖➖➖➖➖
<b>
➲ info 
➤ ️نمایش اطلاعات کلی در مورد سوپر گروه 
➲ who 
➤ ️لیست کاربران گروه 
➲ me 
➤ ️اطلاعاتی در باره شما در گروه 
➲ admins 
➤ ️لیست مدیران گروه 
➲ modlist 
➤ ️لیست مدیران ربات 
➲ kick @username 
➤ ️اخراج کاربر از گروه با آیدی یا ریپلی 
➲ invite @username 
➤ ️دعوت کاربر به گروه 
➲ ban @username 
➤ ️بن کردن کاربر با آیدی یا ریپلی 
➲ unban 
➤ ️خارج کردن کاربر از بن لیست با آیدی یا ریپلی 
➲ id 
➤ ️نمایش آیدی شما و آیدی سوپر گروه 
➲ id from 
➤ گرفتن آیدی از پیام فوروارد شده با ریپلی 
➲ promote @username 
➤ ترفیع رتبه کاربر به عنوان مدیر گروه با آیدی یا ریپلی 
➲ demote @username 
➤ تنزل‌ رتبه مدیر به ممبر معمولی گروه با آیدی یا ریپلی 
➲ setname (groupname) 
➤ ️تعیین نام گروه 
➲ setphoto 
➤ تعیین عکس گروه 
➲ newlink 
➤ ️ساخت لینک جدید برای گروه 
➲ setlink 
➤ ️نشاندن لینک برای گروه 
(بعد از زدن دستور لینک گروه را ارسال کنید.) 
➲ link 
➤ ️گرفتن لینک گروه 
➲ rules 
➤ ️نمایش قوانین گروه 
➲ setrules text 
➤ ️تعیین قوانین گروه نین گروه 
➲ mute [all|audio|gifs|photo|video|service] 
➤️صامت کردن [همه کاربران گروه ، صدا ، گیف ، عکس ، فیلم ، سرویس ]


➲ muteall Xh Ym Zs 
➤ ️صامت کردن همه کاربران تا زمانی مشخص 【بجای X ساعت ، بجای Y دقیقه و بجای Z ثانیه را قراردهید】
مانند:!muteall 2h 12m 56s 
در اینصورت کاربر برای دوساعتو ۱۲ دقیقه و ۵۶ ثانیه نمیتواند چت کند.


➲ unmute 【all|audio|gifs|photo|video|service】
➤ ️خارج کردن از صامت 
➲ setflood [value] 
➤ ️تنظیم حساسیت اسپم(جای [value] عددی بین 1-20قراردهید) 
➲ settings 
➤ ️تنظیمات گروه 
➲ mu @username 
➤ ️ساکت کردن کاربری با آیدی یا ریپلی 
➲ unsilent @username 
➤ ️خارج کردن کاربر از لیست صامت با آیدی یا ریپلی 
➲ silentlist 
➤ ️لیست افراد صامت شده 
➲ mutelist 
➤ ️لیست افراد صامت 
➲ banlist 
➤ ️لیست افراد بن شده 
➲ filterlist 
➤ ️لیست کلمات فیلتر 
➲ mutelist 
➤ ️لیست افراد صامت 
➲ clean 【rules|about|modlist|silentlist|filterlist】
➤ ️پاک کردن [اعلانات ، توضیحات گروه ، لیست مدیران  ، لیست کاربران صامت ، لیست کلمات فیلتر ]
➲ clean msg [value] 
➤️حذف پیام های اخیر گروه (جای value عددی بین 1-200) 

➲ توضیحات: 

➲ برای اجرا دستورات در این ورژن سورس باید از (/!#)در ابتدای دستورات استفاده شه
</b>

<i>➲ Devolopers : </i>
 @MRJOOKER
 @SINGLECYBER]],
	help_text_super =[[
➖➖➖➖➖➖➖ 
<i>
<b>
➲ CYBER SOURCE MODERATOR HELP
</b>
</i>
➖➖➖➖➖➖➖
<b>
➲ info 
➤ ️نمایش اطلاعات کلی در مورد سوپر گروه 
➲ who 
➤ ️لیست کاربران گروه 
➲ me 
➤ ️اطلاعاتی در باره شما در گروه 
➲ admins 
➤ ️لیست مدیران گروه 
➲ modlist 
➤ ️لیست مدیران ربات 
➲ kick @username 
➤ ️اخراج کاربر از گروه با آیدی یا ریپلی 
➲ invite @username 
➤ ️دعوت کاربر به گروه 
➲ ban @username 
➤ ️بن کردن کاربر با آیدی یا ریپلی 
➲ unban 
➤ ️خارج کردن کاربر از بن لیست با آیدی یا ریپلی 
➲ id 
➤ ️نمایش آیدی شما و آیدی سوپر گروه 
➲ id from 
➤ گرفتن آیدی از پیام فوروارد شده با ریپلی 
➲ promote @username 
➤ ترفیع رتبه کاربر به عنوان مدیر گروه با آیدی یا ریپلی 
➲ demote @username 
➤ تنزل‌ رتبه مدیر به ممبر معمولی گروه با آیدی یا ریپلی 
➲ setname (groupname) 
➤ ️تعیین نام گروه 
➲ setphoto 
➤ تعیین عکس گروه 
➲ newlink 
➤ ️ساخت لینک جدید برای گروه 
➲ setlink 
➤ ️نشاندن لینک برای گروه 
(بعد از زدن دستور لینک گروه را ارسال کنید.) 
➲ link 
➤ ️گرفتن لینک گروه 
➲ rules 
➤ ️نمایش قوانین گروه 
➲ setrules text 
➤ ️تعیین قوانین گروه نین گروه 
➲ mute [all|audio|gifs|photo|video|service] 
➤️صامت کردن [همه کاربران گروه ، صدا ، گیف ، عکس ، فیلم ، سرویس ]


➲ muteall Xh Ym Zs 
➤ ️صامت کردن همه کاربران تا زمانی مشخص 【بجای X ساعت ، بجای Y دقیقه و بجای Z ثانیه را قراردهید】
مانند:!muteall 2h 12m 56s 
در اینصورت کاربر برای دوساعتو ۱۲ دقیقه و ۵۶ ثانیه نمیتواند چت کند.


➲ unmute 【all|audio|gifs|photo|video|service】
➤ ️خارج کردن از صامت 
➲ setflood [value] 
➤ ️تنظیم حساسیت اسپم(جای [value] عددی بین 1-20قراردهید) 
➲ settings 
➤ ️تنظیمات گروه 
➲ mu @username 
➤ ️ساکت کردن کاربری با آیدی یا ریپلی 
➲ unsilent @username 
➤ ️خارج کردن کاربر از لیست صامت با آیدی یا ریپلی 
➲ silentlist 
➤ ️لیست افراد صامت شده 
➲ mutelist 
➤ ️لیست افراد صامت 
➲ banlist 
➤ ️لیست افراد بن شده 
➲ filterlist 
➤ ️لیست کلمات فیلتر 
➲ mutelist 
➤ ️لیست افراد صامت 
➲ clean 【rules|about|modlist|silentlist|filterlist】
➤ ️پاک کردن [اعلانات ، توضیحات گروه ، لیست مدیران  ، لیست کاربران صامت ، لیست کلمات فیلتر ]
➲ clean msg [value] 
➤️حذف پیام های اخیر گروه (جای value عددی بین 1-200) 

➲Devolopers: 
@SINGLECYBER
@MRJOOKER
</b>

<i>➲ Devolopers : </i>
 @MRJOOKER
 @SINGLECYBER
SuperGroup Commands:
➖➖➖➖➖➖➖ 
<i>
<b>
➲ CYBER SOURCE MODERATOR HELP
</b>
</i>
➖➖➖➖➖➖➖
<b>
➲ info 
➤ ️نمایش اطلاعات کلی در مورد سوپر گروه 
➲ who 
➤ ️لیست کاربران گروه 
➲ me 
➤ ️اطلاعاتی در باره شما در گروه 
➲ admins 
➤ ️لیست مدیران گروه 
➲ modlist 
➤ ️لیست مدیران ربات 
➲ kick @username 
➤ ️اخراج کاربر از گروه با آیدی یا ریپلی 
➲ invite @username 
➤ ️دعوت کاربر به گروه 
➲ ban @username 
➤ ️بن کردن کاربر با آیدی یا ریپلی 
➲ unban 
➤ ️خارج کردن کاربر از بن لیست با آیدی یا ریپلی 
➲ id 
➤ ️نمایش آیدی شما و آیدی سوپر گروه 
➲ id from 
➤ گرفتن آیدی از پیام فوروارد شده با ریپلی 
➲ promote @username 
➤ ترفیع رتبه کاربر به عنوان مدیر گروه با آیدی یا ریپلی 
➲ demote @username 
➤ تنزل‌ رتبه مدیر به ممبر معمولی گروه با آیدی یا ریپلی 
➲ setname (groupname) 
➤ ️تعیین نام گروه 
➲ setphoto 
➤ تعیین عکس گروه 
➲ newlink 
➤ ️ساخت لینک جدید برای گروه 
➲ setlink 
➤ ️نشاندن لینک برای گروه 
(بعد از زدن دستور لینک گروه را ارسال کنید.) 
➲ link 
➤ ️گرفتن لینک گروه 
➲ rules 
➤ ️نمایش قوانین گروه 
➲ setrules text 
➤ ️تعیین قوانین گروه نین گروه 
➲ mute [all|audio|gifs|photo|video|service] 
➤️صامت کردن [همه کاربران گروه ، صدا ، گیف ، عکس ، فیلم ، سرویس ]


➲ muteall Xh Ym Zs 
➤ ️صامت کردن همه کاربران تا زمانی مشخص 【بجای X ساعت ، بجای Y دقیقه و بجای Z ثانیه را قراردهید】
مانند:!muteall 2h 12m 56s 
در اینصورت کاربر برای دوساعتو ۱۲ دقیقه و ۵۶ ثانیه نمیتواند چت کند.


➲ unmute 【all|audio|gifs|photo|video|service】
➤ ️خارج کردن از صامت 
➲ setflood [value] 
➤ ️تنظیم حساسیت اسپم(جای [value] عددی بین 1-20قراردهید) 
➲ settings 
➤ ️تنظیمات گروه 
➲ mu @username 
➤ ️ساکت کردن کاربری با آیدی یا ریپلی 
➲ unsilent @username 
➤ ️خارج کردن کاربر از لیست صامت با آیدی یا ریپلی 
➲ silentlist 
➤ ️لیست افراد صامت شده 
➲ mutelist 
➤ ️لیست افراد صامت 
➲ banlist 
➤ ️لیست افراد بن شده 
➲ filterlist 
➤ ️لیست کلمات فیلتر 
➲ mutelist 
➤ ️لیست افراد صامت 
➲ clean 【rules|about|modlist|silentlist|filterlist】
➤ ️پاک کردن [اعلانات ، توضیحات گروه ، لیست مدیران  ، لیست کاربران صامت ، لیست کلمات فیلتر ]
➲ clean msg [value] 
➤️حذف پیام های اخیر گروه (جای value عددی بین 1-200) 

➲ توضیحات: 

➲ دستورات فقط  و فقط  بـــدون علامت کار میکنن
</b>

<i>➲ Devolopers : </i>
 @MRJOOKER
 @SINGLECYBER
]],
  }
  serialize_to_file(config, './data/config.lua')
  print('saved config into ./data/config.lua')
end

function on_our_id (id)
  our_id = id
end

function on_user_update (user, what)
  --vardump (user)
end

function on_chat_update (chat, what)
  --vardump (chat)
end

function on_secret_chat_update (schat, what)
  --vardump (schat)
end

function on_get_difference_end ()
end

-- Enable plugins in config.json
function load_plugins()
  for k, v in pairs(_config.enabled_plugins) do
    print("Loading plugin", v)

    local ok, err =  pcall(function()
      local t = loadfile("plugins/"..v..'.lua')()
      plugins[v] = t
    end)

    if not ok then
      print('\27[31mError loading plugin '..v..'\27[39m')
	  print(tostring(io.popen("lua plugins/"..v..".lua"):read('*all')))
      print('\27[31m'..err..'\27[39m')
    end

  end
end

-- custom add
function load_data(filename)

	local f = io.open(filename)
	if not f then
		return {}
	end
	local s = f:read('*all')
	f:close()
	local data = JSON.decode(s)

	return data

end

function save_data(filename, data)

	local s = JSON.encode(data)
	local f = io.open(filename, 'w')
	f:write(s)
	f:close()

end


-- Call and postpone execution for cron plugins
function cron_plugins()

  for name, plugin in pairs(plugins) do
    -- Only plugins with cron function
    if plugin.cron ~= nil then
      plugin.cron()
    end
  end

  -- Called again in 2 mins
  postpone (cron_plugins, false, 120)
end

-- Start and load values
our_id = 0
now = os.time()
math.randomseed(now)
started = false
