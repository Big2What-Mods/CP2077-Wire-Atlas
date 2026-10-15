-- CP2077 WIRE ATLAS
-- Read-only in-game research browser for Cyberpunk 2077
-- CET UI with optional Codeware reflection/resource helpers when available.

local NAME, VER = "CP2077 WIRE ATLAS", "v0.3.39"

local overlay = false
local collapsed = false
local resizeMode = "expanded"

local HOME, HELP, BROWSE, LIST, SEARCH, DETAIL, WRITERS, GRAPH, JOURNAL, ITEM = 1,2,3,4,5,6,7,8,9,10
local page = HOME
local previousPage = HOME

local GRAPH_MAIN, GRAPH_INFORMATION = 1,2
local graphTab = GRAPH_MAIN
local graphResetRequested = false
local graphFitRequested = false
local graphFocusNodeId = nil
local graphFollowEdgeKey = nil
local graphFollowFrames = 0
local graphPreviousUid = nil
local graphPreviousSide = nil
local graphWireMouseLatch = false
local HELP_OVERVIEW, HELP_GUIDES, HELP_TERMS, HELP_TIPS, HELP_FAQ = 1,2,3,4,5
local helpTab = HELP_OVERVIEW
local DETAIL_OVERVIEW, DETAIL_REL, DETAIL_RAW = 1,2,3
local detailTab = DETAIL_OVERVIEW
local WR_WRITERS, WR_READERS, WR_RELATED = 1,2,3
local wrTab = WR_WRITERS
local JOURNAL_TREE, JOURNAL_ENTRY, JOURNAL_RELATED = 1,2,3
local journalTab = JOURNAL_ENTRY
local ITEM_OVERVIEW, ITEM_CONDITIONS, ITEM_RELATED = 1,2,3
local itemTab = ITEM_OVERVIEW
local browseTab = 1
local allItemsPage = 1
local ALL_ITEMS_PAGE_SIZE = 200

local categories = {"Quests","Facts","Journal","Items","Rewards","Achievements","Scenes","Quest Phases"}
local currentCategory = "Quests"
local selected = nil
local selectedHistory = {}
local favorites = {}
local searchText = ""
local searchHasRun = false
local searchFocusRequested = false
local SEARCH_INPUT, SEARCH_RESULTS, SEARCH_FILTERS = 1,2,3
local searchTab = SEARCH_INPUT
local searchKindFilter = nil
local listFilter = ""
local statusText = "READY"
local statusDetail = "Build or refresh the runtime index, then browse or search."
local indexBuilt = false
local indexing = false
local buildQueued = false
local autoBuildPending = true
local autoBuildAttempted = false
local buildProgress = 0
local indexNotes = {}
local indexStats = {journal=0, quests=0, facts=0, items=0, rewards=0, achievements=0, scenes=0, phases=0}
local records = {}
local byKind = {}
local byKey = {}
local searchResults = {}
local directFacts = {}
local lastError = ""
local outputAbs = "bin\\x64\\plugins\\cyber_engine_tweaks\\mods\\CP2077 Wire Atlas\\"
local bridge = { version="not detected", native="not detected", codewareClasses=nil, globals=nil, ok=false }
local liveSessionAttached = false
local wasPlayable = false
local liveStats = {facts=0,journal=0,active=0,succeeded=0,failed=0}

local function probeBridge()
  bridge={version="not detected",native="not detected",codewareClasses=nil,globals=nil,ok=false}
  local ok,v=pcall(function() return Game.WireAtlasBridgeVersion() end)
  if ok and v then bridge.version=tostring(v); bridge.ok=true end
  local okn,n=pcall(function() return Game.WireAtlasNativeMarker() end)
  if okn and n then bridge.native=tostring(n) end
  local okc,c=pcall(function() return Game.WireAtlasCodewareClassCount() end)
  if okc then bridge.codewareClasses=c end
  local okg,g=pcall(function() return Game.WireAtlasCodewareGlobalFunctionCount() end)
  if okg then bridge.globals=g end
end

-- Compact visual language derived from the Journal State Tracer family.
local C = {
  bg={.018,.035,.045,.985}, panel={.025,.055,.070,1}, panel2={.035,.072,.087,1},
  yellow={1,.77,.05,1}, green={0,.92,.45,1}, blue={.18,.58,1,1}, cyan={.15,.78,.88,1},
  red={1,.20,.20,1}, text={.82,.89,.93,1}, dim={.48,.65,.73,1}, border={.13,.45,.52,1}
}
local G = IconGlyphs or {}
-- Keep the icon language intentionally small and consistent.  These are CET-bundled
-- glyphs only; no external image assets are used.
local IC = {
  home=G.Home or "", browse=G.ViewGrid or G.Menu or "", search=G.Magnify or "", help=G.HelpCircle or G.Information or "",
  right=G.ChevronRight or ">", left=G.ArrowLeft or "<", down=G.ChevronDown or "v", up=G.ChevronUp or "^",
  file=G.FileDocument or "", folder=G.Folder or "", star=G.Star or "", link=G.LinkVariant or G.Link or "",
  quest=G.FileDocument or G.ClipboardText or "", fact=G.Database or G.DatabaseOutline or G.CodeBraces or "",
  journal=G.BookOpenPageVariant or G.BookOpen or G.FileDocument or "", item=G.Cube or G.CubeOutline or "",
  reward=G.Gift or G.PackageVariant or "", trophy=G.Trophy or G.Star or "", scene=G.MovieOpen or G.Movie or "",
  phase=G.SourceBranch or G.SourceFork or G.Graph or "", graph=G.SourceBranch or G.Graph or "", info=G.Information or "",
  check=G.Check or "", close=G.Close or "", refresh=G.Refresh or "", save=G.ContentSave or "",
  copy=G.ContentCopy or "", dot=G.CheckboxBlankCircleOutline or ""
}

local function safe(v)
  local ok,s=pcall(tostring,v)
  return ok and s or "<unprintable>"
end
local function lower(v) return string.lower(safe(v or "")) end
local function tc(c,s) ImGui.TextColored(c[1],c[2],c[3],c[4],safe(s)) end
local function sep() ImGui.Spacing(); ImGui.Separator(); ImGui.Spacing() end
local function clampText(s,n) s=safe(s); if #s>n then return s:sub(1,n-3).."..." end; return s end
local function contains(hay,needle) if needle=="" then return true end; return lower(hay):find(lower(needle),1,true)~=nil end
local function normState(v)
  local s=safe(v)
  if s:find("Inactive",1,true) then return "Inactive" end
  if s:find("Succeeded",1,true) then return "Succeeded" end
  if s:find("Failed",1,true) then return "Failed" end
  if s:find("Active",1,true) then return "Active" end
  return s
end
local function stateColor(s)
  s=safe(s)
  if s:find("Succeeded",1,true) then return C.green end
  if s:find("Failed",1,true) then return C.red end
  if s:find("Active",1,true) then return C.blue end
  return C.text
end

local function pushTheme()
  ImGui.PushStyleColor(ImGuiCol.WindowBg,table.unpack(C.bg))
  ImGui.PushStyleColor(ImGuiCol.ChildBg,table.unpack(C.panel))
  ImGui.PushStyleColor(ImGuiCol.Border,table.unpack(C.border))
  ImGui.PushStyleColor(ImGuiCol.Text,table.unpack(C.text))
  ImGui.PushStyleColor(ImGuiCol.Button,.025,.06,.075,1)
  ImGui.PushStyleColor(ImGuiCol.ButtonHovered,.055,.11,.125,1)
  ImGui.PushStyleColor(ImGuiCol.ButtonActive,.075,.14,.155,1)
  ImGui.PushStyleVar(ImGuiStyleVar.WindowRounding,0)
  ImGui.PushStyleVar(ImGuiStyleVar.FrameRounding,0)
  ImGui.PushStyleVar(ImGuiStyleVar.WindowBorderSize,1)
  ImGui.PushStyleVar(ImGuiStyleVar.FrameBorderSize,1)
  ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding,12,12)
  ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing,7,7)
end
local function popTheme() ImGui.PopStyleVar(6); ImGui.PopStyleColor(7) end

local function kindIcon(kind)
  if kind=="Quest" then return IC.quest
  elseif kind=="Fact" then return IC.fact
  elseif kind=="Journal" then return IC.journal
  elseif kind=="Item" then return IC.item
  elseif kind=="Reward" then return IC.reward
  elseif kind=="Achievement" then return IC.trophy
  elseif kind=="Scene" then return IC.scene
  elseif kind=="Quest Phase" then return IC.phase end
  return IC.file
end
local function kindFromCategory(cat)
  if cat=="Quests" then return "Quest" elseif cat=="Facts" then return "Fact" elseif cat=="Journal" then return "Journal"
  elseif cat=="Items" then return "Item" elseif cat=="Rewards" then return "Reward" elseif cat=="Achievements" then return "Achievement"
  elseif cat=="Scenes" then return "Scene" elseif cat=="Quest Phases" then return "Quest Phase" end
  return cat
end

local addRecord, addRelation

local seedWires = {
  ["Fact|q204_done"]={writers={"q204_reborn.questphase :: root node37 :: q204_done = 1"}, readers={}, related={{"Fact|q204_active","same epilogue"},{"Journal|quests/main_quest/epilogues/q204_reborn","terminal journal"}}},
  ["Fact|q203_done"]={writers={"q203_legend.questphase :: root/20 node7 :: q203_done +1"}, readers={}, related={{"Fact|q203_active","same epilogue"},{"Journal|quests/main_quest/epilogues/q203_legend","terminal journal"}}},
  ["Fact|q202_done"]={writers={"q202.questphase :: root node57 :: q202_done +1"}, readers={}, related={{"Fact|q202_active","same epilogue"}}},
  ["Fact|q201_done"]={writers={"q201_heir.questphase :: root/38 node23 :: q201_done = 1"}, readers={}, related={{"Fact|q201_ice","contract choice"},{"Fact|q201_earth","contract choice"}}},
  ["Fact|q201_ice"]={writers={"q201_07_cabin_day_30.scene :: node3001 :: sign contract -> 1","q201_08_cabin_day_30_takemura.scene :: node227 :: sign contract -> 1"}, readers={}, related={{"Fact|q201_earth","exclusive contract pair"},{"Fact|q201_done","terminal clinic"}}},
  ["Fact|q201_earth"]={writers={"q201_07_cabin_day_30.scene :: node3005 :: refuse -> 1","q201_08_cabin_day_30_takemura.scene :: node228 :: return Earth -> 1"}, readers={}, related={{"Fact|q201_ice","exclusive contract pair"},{"Fact|q201_done","terminal clinic"}}},
  ["Fact|q115_v_johnny_solo_ending"]={writers={"q115_02b_ripperdoc_roof.scene :: node1238 :: set 1"}, readers={}, related={{"Journal|quests/meta/09_solo","solo route journal"},{"Fact|q115_did_it_solo","solo success corroboration"}}},
  ["Fact|q115_did_it_solo"]={writers={"q115_solo_the_mikoshi.questphase :: root node12 :: set 1"}, readers={}, related={{"Journal|quests/meta/09_solo","solo success journal"}}},
  ["Fact|q115_smasher_solo_fight"]={writers={"q115_solo_smasher.questphase :: root node33 :: set 1"}, readers={}, related={{"Journal|quests/meta/09_solo/404/02_defeat_smasher","boss objective"}}},
  ["Fact|q115_suicide_ending"]={writers={"q115_02_ripperdoc.questphase :: root/26 node6 :: set 1"}, readers={}, related={}},
  ["Fact|q307_done"]={writers={"q307_cleanup.questphase :: root node19 :: set 1"}, readers={"native One More Gig selector rejects normal PONR continuation when nonzero"}, related={{"Fact|q307_active","Tower lifecycle"}}},
  ["Fact|q305_fact_songbird_dead"]={writers={"q305_10_songbird_finale.scene :: node32 :: set 1"}, readers={}, related={{"Fact|q305_done","branch finale"}}},
  ["Fact|q305_songbird_alive"]={writers={"q305_10_songbird_finale.scene :: node659 :: set 1"}, readers={}, related={{"Fact|q305_done","branch finale"}}},
  ["Fact|q306_reed_killed"]={writers={"q306_10_finale.scene :: node803 :: set 1"}, readers={}, related={{"Fact|q306_launchpad_done","launchpad resolution"}}},
  ["Journal|quests/meta/09_solo"]={writers={"q115_solo_the_mikoshi.questphase :: root node6 :: Succeeded","q115_death.questphase :: root/30/132 node2 :: Failed"}, readers={}, related={{"Fact|q115_did_it_solo","success corroboration"},{"Fact|q115_v_johnny_solo_ending","route selection"}}},
  ["Journal|quests/main_quest/epilogues/q204_reborn"]={writers={"q204_05_bus_station.questphase :: root node6 :: Succeeded"}, readers={}, related={{"Fact|q204_done","terminal fact"}}},
  ["Journal|quests/main_quest/epilogues/q203_legend"]={writers={"q203_cosmos.questphase :: root node22 :: Succeeded"}, readers={}, related={{"Fact|q203_done","terminal fact"}}},
  ["Journal|tarots/tarot_cards/mq033_judgement"]={writers={"q115_00_hanako.questphase :: root/3 node166 :: Active"}, readers={}, related={}},
  ["Journal|tarots/tarot_cards/mq033_the_devil"]={writers={"q115_00_hanako.questphase :: root/3 node168 :: Active"}, readers={}, related={}}
}

local function seedResourceFromWire(owner,text,label)
  if not owner or type(text)~="string" then return end
  local scene=text:match("([%w_%-]+%.scene)")
  local phase=text:match("([%w_%-]+%.questphase)")
  local key=scene or phase
  if not key then return end
  local kind=scene and "Scene" or "Quest Phase"
  local r=addRecord({kind=kind,key=key,name=key,source="Verified wire seed",raw={source=text}})
  if r then
    if kind=="Scene" then indexStats.scenes=#(byKind["Scene"] or {}) else indexStats.phases=#(byKind["Quest Phase"] or {}) end
    addRelation(owner,r,label or "source")
    addRelation(r,owner,label or "source")
  end
end

local function applySeedWires()
  for uid,meta in pairs(seedWires) do
    local r=byKey[uid]
    if r then
      r.writers=meta.writers or r.writers or {}
      r.readers=meta.readers or r.readers or {}
      for _,w in ipairs(r.writers or {}) do seedResourceFromWire(r,w,"writer") end
      for _,rd in ipairs(r.readers or {}) do seedResourceFromWire(r,rd,"reader") end
    end
  end
  for uid,meta in pairs(seedWires) do
    local r=byKey[uid]
    if r and meta.related then
      for _,rel in ipairs(meta.related) do
        local t=byKey[rel[1]]
        if t then addRelation(r,t,rel[2]) end
      end
    end
  end
end

local function clearIndex()
  records={}; byKind={}; byKey={}; searchResults={}
  indexStats={journal=0,quests=0,facts=0,items=0,rewards=0,achievements=0,scenes=0,phases=0}
end
addRecord = function(r)
  if not r or not r.key or r.key=="" then return nil end
  local uid=(r.kind or "Unknown").."|"..r.key
  if byKey[uid] then return byKey[uid] end
  r.uid=uid; r.name=r.name or r.key; r.related=r.related or {}; r.writers=r.writers or {}; r.readers=r.readers or {}; r.raw=r.raw or {}
  records[#records+1]=r; byKey[uid]=r
  byKind[r.kind]=byKind[r.kind] or {}; byKind[r.kind][#byKind[r.kind]+1]=r
  return r
end
addRelation = function(a,b,label)
  if not a or not b or a.uid==b.uid then return end
  a.related[#a.related+1]={target=b.uid,label=label or "related"}
end
local function getByUid(uid) return byKey[uid] end

local factSeeds = {
  "q201_done","q201_ice","q201_earth","q202_active","q202_done","q203_active","q203_done","q203_fact_afterlife_entered",
  "q204_active","q204_done","q307_ready","q307_active","q307_done","q115_v_johnny_solo_ending_choice_added",
  "q115_v_johnny_solo_ending","q115_smasher_solo_fight","q115_did_it_solo","q115_suicide_ending",
  "q115_02_panam_help","q115_02_hanako_help","sq027_done","sq027_panam_ratted_out","sq031_done","sq032_johnny_friend",
  "q305_fact_songbird_dead","q305_songbird_alive","q305_done","q306_reed_killed","q306_finale_deal_done",
  "q306_launchpad_retreated","q306_launchpad_done","q306_done"
}

local function readFact(name)
  local ok,qs=pcall(function() return Game.GetQuestsSystem() end)
  if not ok or not qs then return nil,"QuestsSystem unavailable" end
  local ok2,v=pcall(function() return qs:GetFactStr(name) end)
  if not ok2 then return nil,"Fact read failed" end
  return v,nil
end

local function buildFacts()
  local seen={}
  for _,n in ipairs(factSeeds) do seen[n]=true end
  for n,_ in pairs(directFacts) do seen[n]=true end
  for n,_ in pairs(seen) do
    local v,e=readFact(n)
    local r=addRecord({kind="Fact",key=n,name=n,value=v,error=e,source="FactsDB",raw={identifier=n,currentValue=v}})
    if r then indexStats.facts=indexStats.facts+1 end
  end
end

local function questTokenFromPath(path)
  local p=safe(path)
  return p:match("/(q%d%d%d)[/_]") or p:match("/(q%d%d%d)$") or p:match("/(sq%d%d%d)[/_]") or p:match("/(mq%d%d%d)[/_]")
end

local function isPlayableSession()
  local okP,player=pcall(function() return Game.GetPlayer() end)
  if not okP or not player then return false end
  local okA,attached=pcall(function() return player:IsAttached() end)
  if not okA or not attached then return false end
  local okR,requests=pcall(function() return Game.GetSystemRequestsHandler() end)
  if not okR or not requests then return false end
  local okPre,preGame=pcall(function() return requests:IsPreGame() end)
  if not okPre or preGame then return false end
  return true
end

local function scanJournal()
  local ok,jm=pcall(function() return Game.GetJournalManager() end)
  if not ok or not jm then return end
  local okf,filter=pcall(function()
    local f=JournalRequestStateFilter.new(); f.inactive=true; f.active=true; f.succeeded=true; f.failed=true; return f
  end)
  if not okf or not filter then return end
  local seen={}; local questMap={}
  local function walk(e,path,parentUid,depth)
    if not e or depth>80 then return end
    local okid,id=pcall(function() return tostring(e:GetId()) end); if not okid then id="?" end
    local oks,st=pcall(function() return jm:GetEntryState(e) end); st=oks and normState(st) or "Unknown"
    local okh,h=pcall(function() return jm:GetEntryHash(e)%4294967296 end); h=okh and h or nil
    local key=(h and tostring(h)) or path
    if seen[key] then return end; seen[key]=true
    local rr=addRecord({kind="Journal",key=path,name=id,path=path,id=id,hash=h,state=st,source="JournalManager",parent=parentUid,depth=depth,raw={path=path,id=id,hash=h,state=st}})
    if rr then
      indexStats.journal=indexStats.journal+1
      local qt=questTokenFromPath(path)
      if qt then
        local q=questMap[qt]
        if not q then
          q=addRecord({kind="Quest",key=qt,name=qt,source="JournalManager",raw={questId=qt}}); questMap[qt]=q; indexStats.quests=indexStats.quests+1
        end
        addRelation(q,rr,"journal")
        addRelation(rr,q,"quest")
      end
      if parentUid then local pr=getByUid(parentUid); if pr then addRelation(pr,rr,"child"); addRelation(rr,pr,"parent") end end
    end
    local okc,children=pcall(function() return jm:GetChildren(e,filter) end)
    if okc and type(children)=="table" then
      for _,ch in ipairs(children) do
        local cid="?"; pcall(function() cid=tostring(ch:GetId()) end)
        walk(ch,path.."/"..cid,rr and rr.uid or parentUid,depth+1)
      end
    end
  end
  for _,root in ipairs({{"quests","gameJournalPrimaryFolderEntry"},{"ep1/quests","gameJournalPrimaryFolderEntry"},{"tarots","gameJournalPrimaryFolderEntry"}}) do
    local oke,e=pcall(function() return jm:GetEntryByString(root[1],root[2]) end)
    if oke and e then walk(e,root[1],nil,0) end
  end
end

local function refreshLiveState()
  if not indexBuilt or not isPlayableSession() then return false end
  liveStats={facts=0,journal=0,active=0,succeeded=0,failed=0}

  for _,r in ipairs(byKind["Fact"] or {}) do
    local v,e=readFact(r.key)
    if not e then
      r.value=v
      r.error=nil
      r.raw=r.raw or {}
      r.raw.currentValue=v
      liveStats.facts=liveStats.facts+1
    end
  end

  local ok,jm=pcall(function() return Game.GetJournalManager() end)
  if ok and jm then
    local okf,filter=pcall(function()
      local f=JournalRequestStateFilter.new(); f.inactive=true; f.active=true; f.succeeded=true; f.failed=true; return f
    end)
    if okf and filter then
      local seen={}
      local function walk(e,path,depth)
        if not e or depth>80 then return end
        local okh,h=pcall(function() return jm:GetEntryHash(e)%4294967296 end)
        local key=okh and tostring(h) or path
        if seen[key] then return end
        seen[key]=true
        local r=byKey["Journal|"..path]
        if r then
          local oks,st=pcall(function() return jm:GetEntryState(e) end)
          if oks then
            st=normState(st)
            r.state=st
            r.raw=r.raw or {}
            r.raw.state=st
            liveStats.journal=liveStats.journal+1
            if st=="Active" then liveStats.active=liveStats.active+1
            elseif st=="Succeeded" then liveStats.succeeded=liveStats.succeeded+1
            elseif st=="Failed" then liveStats.failed=liveStats.failed+1 end
          end
        end
        local okc,children=pcall(function() return jm:GetChildren(e,filter) end)
        if okc and type(children)=="table" then
          for _,ch in ipairs(children) do
            local cid="?"; pcall(function() cid=tostring(ch:GetId()) end)
            walk(ch,path.."/"..cid,depth+1)
          end
        end
      end
      for _,root in ipairs({{"quests","gameJournalPrimaryFolderEntry"},{"ep1/quests","gameJournalPrimaryFolderEntry"},{"tarots","gameJournalPrimaryFolderEntry"}}) do
        local oke,e=pcall(function() return jm:GetEntryByString(root[1],root[2]) end)
        if oke and e then walk(e,root[1],0) end
      end
    end
  end

  liveSessionAttached=true
  statusText="LIVE"
  statusDetail="Playable save detected. Live FactsDB and JournalManager state attached."
  print(string.format("[WIRE ATLAS] live session attached: facts=%d journal=%d active=%d succeeded=%d failed=%d",
    liveStats.facts,liveStats.journal,liveStats.active,liveStats.succeeded,liveStats.failed))
  return true
end

local function extractReadable(value)
  if value==nil then return "" end
  local raw=safe(value)
  local readable=raw:match("%-%-%[%[%s*(.-)%s*%-%-%]%]")
  if readable and readable~="" then return readable end
  return raw
end

local function recordId(rec)
  local ok,id=pcall(function() return rec:GetID() end)
  if ok and id~=nil then
    local text=extractReadable(id)
    if text~="" then return text end
  end
  return safe(rec)
end
local function locText(value)
  local s=safe(value)
  local ok,res=pcall(function() return GetLocalizedTextByKey(s) end)
  if ok and res and res~="" and res~=s then return res end
  local ok2,res2=pcall(function() return GetLocalizedText(s) end)
  if ok2 and res2 and res2~="" and res2~=s then return res2 end
  return nil
end
local function tryMethod(obj,name)
  local ok,v=pcall(function() return obj[name](obj) end)
  if ok then return v end
  return nil
end
local function tweakName(rec,id)
  local candidates={"DisplayName","Name","LocalizedName","ItemName","Description"}
  for _,m in ipairs(candidates) do
    local v=tryMethod(rec,m)
    if v~=nil then
      local s=safe(v); local l=locText(s)
      if l and l~="" then return l end
      if s~="" and not s:find("LocKey",1,true) then return s end
    end
  end
  return id
end
local function itemRecordId(rec)
  local ok,id=pcall(function() return rec:GetID() end)
  if ok and id~=nil then
    -- CET exposes the real TweakDB path through TDBID.ToStringDEBUG().
    -- tostring(GetID()) can fall back to an opaque ToCName/hash dump, which is
    -- what the old Items browser was showing.
    local okd,dbg=pcall(function() return TDBID.ToStringDEBUG(id) end)
    if okd and dbg~=nil then
      local s=safe(dbg)
      if s~="" and not s:find("ToCName",1,true) and not s:find("hash_lo",1,true) then return s end
    end
    local okv,v=pcall(function() return id.value end)
    if okv and v~=nil then
      local s=safe(v)
      if s~="" and not s:find("ToCName",1,true) and not s:find("hash_lo",1,true) then return s end
    end
  end
  return recordId(rec)
end
local function itemRecordName(rec,id)
  -- Ask the record for its actual localized display name first.  Pass the raw
  -- localization key/CName to Game.GetLocalizedText; stringifying it first loses
  -- the information CET needs to resolve the key on current builds.
  local candidates={"DisplayName","LocalizedName","ItemName","Name"}
  for _,m in ipairs(candidates) do
    local v=tryMethod(rec,m)
    if v~=nil then
      local okg,g=pcall(function() return Game.GetLocalizedText(v) end)
      if okg and g~=nil then
        local gs=safe(g)
        if gs~="" and gs~=safe(v) and not gs:find("LocKey",1,true) and not gs:find("ToCName",1,true) then return gs end
      end
      local okv,sv=pcall(function() return v.value end)
      if okv and sv~=nil then
        local vs=safe(sv)
        if vs~="" and not vs:find("LocKey",1,true) and not vs:find("ToCName",1,true) then return vs end
      end
      local raw=safe(v)
      if raw~="" and not raw:find("LocKey",1,true) and not raw:find("ToCName",1,true) and not raw:find("hash_lo",1,true) then return raw end
    end
  end
  return id
end
local function scanTweakType(kind,typeName,limit)
  local ok,recs=pcall(function() return TweakDB:GetRecords(typeName) end)
  if not ok or type(recs)~="table" then return 0 end
  local n=0
  for _,rec in ipairs(recs) do
    local id,name
    if kind=="Item" then
      id=itemRecordId(rec)
      name=itemRecordName(rec,id)
    else
      id=recordId(rec)
      name=tweakName(rec,id)
    end
    local r=addRecord({kind=kind,key=id,name=name,source="TweakDB",record=rec,recordType=typeName,raw={id=id,type=typeName}})
    if r then n=n+1 end
    if limit and n>=limit then break end
  end
  return n
end
local function scanTweakDB()
  -- These calls are read-only. Failures are ignored because record class names can vary by build.
  local itemTypes={"gamedataWeaponItem_Record","gamedataCyberware_Record","gamedataClothing_Record","gamedataConsumableItem_Record"}
  local rewardTypes={"gamedataReward_Record","gamedataRewardBase_Record","gamedataRewardSet_Record"}
  for _,t in ipairs(itemTypes) do indexStats.items=indexStats.items+scanTweakType("Item",t) end
  for _,t in ipairs(rewardTypes) do indexStats.rewards=indexStats.rewards+scanTweakType("Reward",t) end
  indexStats.achievements=indexStats.achievements+scanTweakType("Achievement","gamedataAchievement_Record")
end

local function relateByToken()
  local tokenBuckets={}
  local function tokensFor(r)
    local s=lower((r.key or "").." "..(r.path or "").." "..(r.name or ""))
    local out={}
    for tok in s:gmatch("[qs]q%d%d%d") do out[tok]=true end
    for tok in s:gmatch("q%d%d%d") do out[tok]=true end
    return out
  end
  for _,r in ipairs(records) do
    for tok,_ in pairs(tokensFor(r)) do tokenBuckets[tok]=tokenBuckets[tok] or {}; tokenBuckets[tok][#tokenBuckets[tok]+1]=r end
  end
  for tok,b in pairs(tokenBuckets) do
    if #b<=80 then
      for i=1,#b do for j=i+1,#b do addRelation(b[i],b[j],tok); addRelation(b[j],b[i],tok) end end
    end
  end
end

local function seedKnownRecords()
  -- Seed only identifiers that were already verified by the shipped-data research.
  -- Live readers overwrite/augment these entries when the relevant systems are available.
  for _,name in ipairs(factSeeds) do
    addRecord({kind="Fact",key=name,name=name,source="FactsDB",raw={identifier=name}})
  end
  for uid,_ in pairs(seedWires) do
    local kind,key=uid:match("^([^|]+)|(.+)$")
    if kind=="Journal" and key then
      local name=key:match("([^/]+)$") or key
      addRecord({kind="Journal",key=key,name=name,path=key,source="Verified wire seed",state="Unknown",raw={path=key}})
    end
  end
end

local function addIndexNote(step,msg)
  indexNotes[#indexNotes+1]=step..": "..safe(msg)
end

local function runIndexStep(step,progress,fn)
  buildProgress=progress
  statusDetail=step.."..."
  local ok,err=pcall(fn)
  if not ok then addIndexNote(step,err) end
  return ok
end

local function rebuildIndex()
  if indexing then return end
  indexing=true
  buildQueued=false
  buildProgress=.02
  statusText="INDEXING"
  statusDetail="Preparing read-only runtime index..."
  lastError=""
  indexNotes={}
  clearIndex()

  runIndexStep("Seeding verified identifiers",.08,seedKnownRecords)
  runIndexStep("Reading FactsDB",.18,buildFacts)
  runIndexStep("Walking JournalManager",.38,scanJournal)
  runIndexStep("Enumerating TweakDB records",.62,scanTweakDB)
  runIndexStep("Linking records",.86,relateByToken)
  runIndexStep("Applying verified writer/reader wires",.94,applySeedWires)

  buildProgress=1
  indexing=false
  indexBuilt=(#records>0)
  statusText=indexBuilt and "READY" or "ERROR"
  if #indexNotes>0 then
    lastError=table.concat(indexNotes," | ")
    statusDetail=indexBuilt and "Index ready with partial-reader notes." or "Index build failed; see note."
  else
    statusDetail=indexBuilt and "Runtime index ready." or "No records were indexed."
  end

  print(string.format("[WIRE ATLAS] index complete: %d records | quests=%d facts=%d journal=%d items=%d rewards=%d achievements=%d scenes=%d phases=%d",
    #records,#(byKind["Quest"] or {}),#(byKind["Fact"] or {}),#(byKind["Journal"] or {}),#(byKind["Item"] or {}),
    #(byKind["Reward"] or {}),#(byKind["Achievement"] or {}),#(byKind["Scene"] or {}),#(byKind["Quest Phase"] or {})))
  for _,note in ipairs(indexNotes) do print("[WIRE ATLAS] "..note) end
  if indexBuilt and isPlayableSession() then refreshLiveState() end
end

local function doSearch(q)
  q=q or searchText; searchResults={}; searchHasRun=true; local lq=lower(q)
  if lq=="" then return end
  -- Direct fact lookup lets an expert search a fact that was not in the seed list.
  if not lq:find("/",1,true) and not lq:find(".",1,true) and #q>2 then
    local v,e=readFact(q)
    if not e then directFacts[q]=true; local r=addRecord({kind="Fact",key=q,name=q,value=v,source="FactsDB",raw={identifier=q,currentValue=v}}); if r then searchResults[#searchResults+1]=r end end
  end
  local seen={}
  for _,r in ipairs(records) do
    if contains(r.key,q) or contains(r.name,q) or contains(r.path,q) or contains(r.source,q) then
      if not seen[r.uid] then searchResults[#searchResults+1]=r; seen[r.uid]=true end
    end
  end
  table.sort(searchResults,function(a,b)
    local ae=(lower(a.key)==lq) and 0 or 1; local be=(lower(b.key)==lq) and 0 or 1
    if ae~=be then return ae<be end
    if a.kind~=b.kind then return a.kind<b.kind end
    return lower(a.name)<lower(b.name)
  end)
end

local function go(p,rec)
  if p~=page then previousPage=page end
  page=p
  if rec then selected=rec; selectedHistory[#selectedHistory+1]=rec.uid end
  if p==DETAIL then detailTab=DETAIL_OVERVIEW
  elseif p==WRITERS then wrTab=WR_WRITERS
  elseif p==GRAPH then
    graphTab=GRAPH_MAIN
    graphFitRequested=true
    if rec then graphPreviousUid=nil; graphPreviousSide=nil end
  elseif p==JOURNAL then journalTab=JOURNAL_ENTRY
  elseif p==ITEM then itemTab=ITEM_OVERVIEW end
end
local function openRecord(r)
  if not r then return end
  if r.kind=="Journal" then go(JOURNAL,r)
  elseif r.kind=="Item" or r.kind=="Reward" then go(ITEM,r)
  else go(DETAIL,r) end
end

local function header()
  local chevron=collapsed and IC.right or IC.down
  ImGui.PushStyleColor(ImGuiCol.Button,0,0,0,0); ImGui.PushStyleColor(ImGuiCol.ButtonHovered,0,0,0,0); ImGui.PushStyleColor(ImGuiCol.ButtonActive,0,0,0,0); ImGui.PushStyleColor(ImGuiCol.Border,0,0,0,0); ImGui.PushStyleColor(ImGuiCol.Text,table.unpack(C.yellow))
  if ImGui.Button(chevron.."##collapse",28,26) then collapsed=not collapsed; resizeMode=collapsed and "collapsed" or "expanded" end
  ImGui.PopStyleColor(5); ImGui.SameLine(); tc(C.yellow,NAME)
  if not collapsed then sep() end
end
local function navButton(label,target,width)
  local active=(page==target) or (target==BROWSE and page==LIST) or (target==SEARCH and page==SEARCH) or (target==HELP and page==HELP)
  if active then ImGui.PushStyleColor(ImGuiCol.Button,.10,.12,.10,1); ImGui.PushStyleColor(ImGuiCol.Text,table.unpack(C.yellow)) end
  if ImGui.Button(label,width or 116,34) then
    if target==SEARCH then
      searchTab=SEARCH_INPUT
      searchFocusRequested=true
    end
    go(target)
  end
  if active then ImGui.PopStyleColor(2) end
end
local function mainNav()
  local avail=ImGui.GetContentRegionAvail()
  local w=(avail-21)/4
  navButton((IC.home~="" and IC.home.."  " or "").."HOME",HOME,w); ImGui.SameLine()
  navButton((IC.browse~="" and IC.browse.."  " or "").."BROWSE",BROWSE,w); ImGui.SameLine()
  navButton((IC.search~="" and IC.search.."  " or "").."SEARCH",SEARCH,w); ImGui.SameLine()
  navButton((IC.help~="" and IC.help.."  " or "").."HELP",HELP,w)
  sep()
end
local paddedGlyphButton

local function subTabs(labels,current,setter)
  local icons={
    OVERVIEW=IC.info, GUIDES=IC.journal, TERMS=IC.file, TIPS=IC.star, FAQ=IC.help,
    CATEGORIES=IC.browse, ["ALL ITEMS"]=IC.item, RECENT=IC.refresh, FAVORITES=IC.star,
    WRITERS=IC.quest, READERS=IC.search, RELATED=IC.link,
    GRAPH=IC.graph, INFORMATION=IC.info,
    TREE=IC.folder, ENTRY=IC.journal, CONDITIONS=IC.check
  }
  local avail=ImGui.GetContentRegionAvail()
  local n=#labels
  local w=(avail-(n-1)*6)/n
  for i,l in ipairs(labels) do
    if i>1 then ImGui.SameLine() end
    local icon=icons[l] or IC.file or ""
    if paddedGlyphButton("subtab"..i,l,icon,w,32,current==i) then setter(i) end
  end
  sep()
end

local function breadcrumb(parts)
end
local function statusRow()
  local c=indexing and C.yellow or C.green
  tc(c,"Status: "..statusText); ImGui.SameLine(); tc(C.dim,statusDetail)
  if lastError~="" then tc(C.red,"Index note: "..clampText(lastError,120)) end
end
local function inputText(label,value,maxLen)
  local ok,a,b=pcall(ImGui.InputText,label,value,maxLen or 256)
  if not ok then return false,value end
  if type(a)=="boolean" then return a,b or value end
  if type(a)=="string" then return a~=value,a end
  return false,value
end
local function recordButton(r,idx)
  local icon=kindIcon(r.kind)
  tc(C.cyan,icon~="" and icon or "•")
  ImGui.SameLine()
  tc(C.yellow,r.kind)
  ImGui.SameLine()
  ImGui.Text(clampText(r.name or r.key,52))
  tc(C.dim,clampText(r.key,92))
  if r.state then
    tc(stateColor(r.state),"State: "..r.state)
  elseif r.value~=nil then
    tc(C.dim,"Value: "..safe(r.value))
  end
  if paddedGlyphButton("recOpen"..safe(idx)..r.uid,"OPEN",kindIcon(r.kind),170,32,false) then openRecord(r) end
  ImGui.Spacing()
end

local function categoryLabel(cat)
  local kind=kindFromCategory(cat)
  return (kindIcon(kind)~="" and kindIcon(kind).."  " or "")..cat
end

local categoryHint = {
  Quests="Story and side quests", Facts="Game-state variables", Journal="Entries and objectives", Items="Weapons, gear and loot",
  Rewards="Reward sets and grants", Achievements="Game achievements", Scenes="Scene resources", ["Quest Phases"]="Quest logic and nodes"
}
local dashU32

local function browseGridCard(id,icon,title,line2,line3,w,h,onClick)
  local x,y=ImGui.GetCursorScreenPos()
  local draw=ImGui.GetWindowDrawList()
  local bh=h or 86

  ImGui.InvisibleButton("##browseGridCard"..id,w,bh)
  local hovered=ImGui.IsItemHovered()
  local clicked=ImGui.IsItemClicked()

  local fill=hovered and dashU32({.045,.095,.110,1}) or dashU32({.020,.050,.063,1})
  local border=hovered and dashU32(C.cyan) or dashU32(C.border)
  ImGui.ImDrawListAddRectFilled(draw,x,y,x+w,y+bh,fill,0)
  ImGui.ImDrawListAddRect(draw,x,y,x+w,y+bh,border,0,0,1.0)

  -- Locked Quests-style internal spacing baseline.
  local leftPad=14
  local iconX=x+leftPad
  local titleX=x+42
  local titleY=y+10
  local line2Y=y+36
  local line3Y=y+58

  local glyph=safe(icon or "")
  local glyphW,glyphH=ImGui.CalcTextSize(glyph)
  local titleW,titleH=ImGui.CalcTextSize(title)
  local l2=safe(line2 or "")
  local l3=safe(line3 or "")
  local l2W,l2H=ImGui.CalcTextSize(l2)
  local l3W,l3H=ImGui.CalcTextSize(l3)

  ImGui.ImDrawListAddText(draw,iconX,titleY,dashU32(C.text),glyph)
  ImGui.ImDrawListAddText(draw,titleX,titleY,dashU32(C.text),title)
  if l2~="" then ImGui.ImDrawListAddText(draw,titleX,line2Y,dashU32(C.text),l2) end
  if l3~="" then ImGui.ImDrawListAddText(draw,titleX,line3Y,dashU32(C.text),l3) end

  if clicked and onClick then onClick() end
end

local function categoryCard(cat,idx,w,h)
  local kind=kindFromCategory(cat)
  local count=byKind[kind] and #byKind[kind] or 0
  local icon=kindIcon(kind)
  browseGridCard(
    "cat"..idx,
    icon,
    cat,
    categoryHint[cat] or "",
    tostring(count).." indexed",
    w,
    h or 82,
    function()
      currentCategory=cat
      listFilter=""
      go(LIST)
    end
  )
end

local function componentLine()
  local okNative=bridge.native~="not detected"
  tc(bridge.ok and C.green or C.red,"REDscript "..(bridge.ok and "OK" or "missing"))
  ImGui.SameLine(); tc(okNative and C.green or C.red,"  Native "..(okNative and "OK" or "missing"))
  if bridge.codewareClasses~=nil then
    ImGui.SameLine(); tc(C.dim,"  Codeware "..safe(bridge.codewareClasses).." classes")
  end
end

local function centeredText(text,color)
  local avail=ImGui.GetContentRegionAvail()
  local tw,th=ImGui.CalcTextSize(safe(text))
  local x=ImGui.GetCursorPosX()+math.max(0,(avail-tw)*.5)
  ImGui.SetCursorPosX(x)
  if color then tc(color,text) else ImGui.Text(text) end
end

dashU32 = function(c)
  local ok,v=pcall(function() return ImGui.GetColorU32(c[1],c[2],c[3],c[4]) end)
  if ok and v then return v end
  local function b(x) return math.max(0,math.min(255,math.floor((x or 0)*255+.5))) end
  local r,g,bb,a=b(c[1]),b(c[2]),b(c[3]),b(c[4] or 1)
  return r + g*256 + bb*65536 + a*16777216
end

-- Crisp vector icons rendered directly at final size.
-- No small glyph is being stretched; every icon is built from draw-list primitives.
local function drawVectorIcon(draw,kind,cx,cy,size,col)
  local c=dashU32(col or C.cyan)
  local t=math.max(1.6,size*.075)
  local x0,y0=cx-size*.5,cy-size*.5
  local x1,y1=cx+size*.5,cy+size*.5

  local function line(ax,ay,bx,by,th)
    ImGui.ImDrawListAddLine(draw,ax,ay,bx,by,c,th or t)
  end
  local function rect(ax,ay,bx,by,round,th)
    ImGui.ImDrawListAddRect(draw,ax,ay,bx,by,c,round or 0,0,th or t)
  end
  local function fillrect(ax,ay,bx,by,round)
    ImGui.ImDrawListAddRectFilled(draw,ax,ay,bx,by,c,round or 0)
  end
  local function circle(x,y,r,th)
    ImGui.ImDrawListAddCircle(draw,x,y,r,c,24,th or t)
  end
  local function fillcircle(x,y,r)
    ImGui.ImDrawListAddCircleFilled(draw,x,y,r,c,24)
  end

  if kind=="browse" then
    local gap=size*.08
    local cell=(size-gap*2)/3
    for rr=0,2 do
      for cc=0,2 do
        local ax=x0+cc*(cell+gap)
        local ay=y0+rr*(cell+gap)
        rect(ax,ay,ax+cell,ay+cell,1,t)
      end
    end

  elseif kind=="context" then
    -- Pulse / signal trace.
    local mid=cy
    local p={
      {x0,mid},{cx-size*.24,mid},
      {cx-size*.13,cy-size*.24},
      {cx,cy+size*.28},
      {cx+size*.13,cy-size*.16},
      {cx+size*.24,mid},{x1,mid}
    }
    for i=1,#p-1 do line(p[i][1],p[i][2],p[i+1][1],p[i+1][2],t) end

  elseif kind=="recent" then
    circle(cx,cy,size*.42,t)
    line(cx,cy,cx,cy-size*.23,t)
    line(cx,cy,cx+size*.20,cy+size*.08,t)
    line(cx-size*.30,cy-size*.30,cx-size*.18,cy-size*.39,t)

  elseif kind=="Quest" then
    rect(x0+size*.15,y0+size*.08,x1-size*.15,y1-size*.08,2,t)
    line(x0+size*.28,cy-size*.15,x1-size*.25,cy-size*.15,t)
    line(x0+size*.28,cy,x1-size*.25,cy,t)
    line(x0+size*.28,cy+size*.15,x1-size*.38,cy+size*.15,t)

  elseif kind=="Fact" then
    -- Database stack.
    local w=size*.34
    for off=-1,0,1 do
      local yy=cy+off*size*.19
      rect(cx-w,yy-size*.07,cx+w,yy+size*.07,size*.07,t)
    end

  elseif kind=="Journal" then
    -- Open book.
    line(cx, y0+size*.10, cx, y1-size*.10,t)
    line(cx, y0+size*.10, x0+size*.12, y0+size*.18,t)
    line(x0+size*.12,y0+size*.18,x0+size*.12,y1-size*.12,t)
    line(x0+size*.12,y1-size*.12,cx,y1-size*.04,t)
    line(cx,y0+size*.10,x1-size*.12,y0+size*.18,t)
    line(x1-size*.12,y0+size*.18,x1-size*.12,y1-size*.12,t)
    line(x1-size*.12,y1-size*.12,cx,y1-size*.04,t)

  elseif kind=="Item" then
    -- Upright package / box.
    rect(x0+size*.12,y0+size*.18,x1-size*.12,y1-size*.10,2,t)
    line(x0+size*.12,y0+size*.38,x1-size*.12,y0+size*.38,t)
    line(cx,y0+size*.18,cx,y1-size*.10,t)
    line(cx-size*.14,y0+size*.18,cx-size*.14,y0+size*.38,t)
    line(cx+size*.14,y0+size*.18,cx+size*.14,y0+size*.38,t)

  elseif kind=="Reward" then
    rect(x0+size*.12,cy-size*.03,x1-size*.12,y1-size*.10,2,t)
    rect(x0+size*.06,y0+size*.18,x1-size*.06,cy-size*.03,2,t)
    line(cx,y0+size*.18,cx,y1-size*.10,t)
    line(cx, y0+size*.18, cx-size*.16, y0+size*.04,t)
    line(cx, y0+size*.18, cx+size*.16, y0+size*.04,t)

  elseif kind=="Achievement" then
    -- Trophy.
    rect(cx-size*.20,y0+size*.08,cx+size*.20,cy+size*.02,2,t)
    line(cx-size*.20,y0+size*.16,x0+size*.06,y0+size*.16,t)
    line(x0+size*.06,y0+size*.16,x0+size*.12,cy-size*.02,t)
    line(x0+size*.12,cy-size*.02,cx-size*.20,cy-size*.02,t)
    line(cx+size*.20,y0+size*.16,x1-size*.06,y0+size*.16,t)
    line(x1-size*.06,y0+size*.16,x1-size*.12,cy-size*.02,t)
    line(x1-size*.12,cy-size*.02,cx+size*.20,cy-size*.02,t)
    line(cx,cy+size*.02,cx,cy+size*.26,t)
    line(cx-size*.16,cy+size*.26,cx+size*.16,cy+size*.26,t)

  elseif kind=="Scene" then
    -- Clapperboard.
    rect(x0+size*.10,cy-size*.06,x1-size*.10,y1-size*.12,2,t)
    rect(x0+size*.10,y0+size*.10,x1-size*.10,cy-size*.06,2,t)
    line(x0+size*.18,y0+size*.12,x0+size*.30,cy-size*.08,t)
    line(x0+size*.38,y0+size*.12,x0+size*.50,cy-size*.08,t)
    line(x0+size*.58,y0+size*.12,x0+size*.70,cy-size*.08,t)

  elseif kind=="Quest Phase" then
    -- Logic nodes.
    fillcircle(x0+size*.16,cy-size*.18,size*.055)
    fillcircle(cx+size*.08,y0+size*.16,size*.055)
    fillcircle(x1-size*.14,cy+size*.20,size*.055)
    line(x0+size*.21,cy-size*.18,cx+size*.03,y0+size*.19,t)
    line(cx+size*.11,y0+size*.21,x1-size*.17,cy+size*.15,t)

  else
    -- Generic crisp node/diamond.
    line(cx,y0+size*.08,x1-size*.08,cy,t)
    line(x1-size*.08,cy,cx,y1-size*.08,t)
    line(cx,y1-size*.08,x0+size*.08,cy,t)
    line(x0+size*.08,cy,cx,y0+size*.08,t)
  end
end

local function dashboardTile(id,iconKind,title,desc1,desc2,w,h,iconColor,onClick,iconSize)
  local x,y=ImGui.GetCursorScreenPos()
  local draw=ImGui.GetWindowDrawList()

  ImGui.InvisibleButton("##dashTile"..id,w,h)
  local hovered=ImGui.IsItemHovered()
  local clicked=ImGui.IsItemClicked()

  local fill=hovered and dashU32({.045,.095,.110,1}) or dashU32({.020,.050,.063,1})
  local border=hovered and dashU32(C.cyan) or dashU32(C.border)
  ImGui.ImDrawListAddRectFilled(draw,x,y,x+w,y+h,fill,4)
  ImGui.ImDrawListAddRect(draw,x,y,x+w,y+h,border,4,0,1.5)

  local isz=iconSize or 30
  drawVectorIcon(draw,iconKind,x+w*.5,y+10+isz*.5,isz,iconColor or C.cyan)

  local function drawCentered(txt,yy,col)
    txt=safe(txt)
    local tw,th=ImGui.CalcTextSize(txt)
    ImGui.ImDrawListAddText(draw,x+(w-tw)*.5,yy,dashU32(col),txt)
  end

  local titleY=y+17+isz
  drawCentered(title,titleY,C.text)
  if desc1 and desc1~="" then drawCentered(desc1,titleY+24,C.dim) end
  if desc2 and desc2~="" then drawCentered(desc2,titleY+43,C.dim) end

  if clicked and onClick then onClick() end
end


local function vectorControlButton(id,label,iconKind,w,h,active,iconColor)
  local x,y=ImGui.GetCursorScreenPos()
  local draw=ImGui.GetWindowDrawList()
  ImGui.InvisibleButton("##vcb"..id,w,h)
  local hovered=ImGui.IsItemHovered()
  local clicked=ImGui.IsItemClicked()

  local fill
  if active then fill=dashU32({.10,.12,.10,1})
  elseif hovered then fill=dashU32({.045,.095,.110,1})
  else fill=dashU32({.020,.050,.063,1}) end
  local border=hovered and dashU32(C.cyan) or dashU32(C.border)
  local textCol=active and dashU32(C.yellow) or dashU32(C.text)

  ImGui.ImDrawListAddRectFilled(draw,x,y,x+w,y+h,fill,3)
  ImGui.ImDrawListAddRect(draw,x,y,x+w,y+h,border,3,0,1.4)

  local iconSize=math.min(20,h-10)
  local labelW,labelH=ImGui.CalcTextSize(label)
  local total=labelW + (iconKind and 28 or 0)
  local start=x+(w-total)*.5
  if iconKind then
    drawVectorIcon(draw,iconKind,start+iconSize*.5,y+h*.5,iconSize,iconColor or (active and C.yellow or C.cyan))
    start=start+28
  end
  ImGui.ImDrawListAddText(draw,start,y+(h-labelH)*.5,textCol,label)
  return clicked,hovered
end

paddedGlyphButton = function(id,label,glyph,w,h,active)
  local padX=14
  local gap=10
  local bh=math.max(h or 32,32)
  local icon=safe(glyph or "")
  local labelW,labelH=ImGui.CalcTextSize(label)
  local iconW,iconH=ImGui.CalcTextSize(icon)
  local contentW=labelW + (icon~="" and (iconW+gap) or 0)
  local bw=math.max(w or 0,contentW+padX*2)

  local x,y=ImGui.GetCursorScreenPos()
  local draw=ImGui.GetWindowDrawList()
  ImGui.InvisibleButton("##pgb"..id,bw,bh)
  local hovered=ImGui.IsItemHovered()
  local clicked=ImGui.IsItemClicked()

  local fill
  if active then fill=dashU32({.10,.12,.10,1})
  elseif hovered then fill=dashU32({.045,.095,.110,1})
  else fill=dashU32({.020,.050,.063,1}) end
  local border=active and dashU32(C.yellow) or (hovered and dashU32(C.cyan) or dashU32(C.border))
  local textCol=active and dashU32(C.yellow) or dashU32(C.text)

  ImGui.ImDrawListAddRectFilled(draw,x,y,x+bw,y+bh,fill,3)
  ImGui.ImDrawListAddRect(draw,x,y,x+bw,y+bh,border,3,0,active and 1.6 or 1.3)

  local start=x+(bw-contentW)*.5
  if icon~="" then
    ImGui.ImDrawListAddText(draw,start,y+(bh-iconH)*.5,dashU32(active and C.yellow or C.text),icon)
    start=start+iconW+gap
  end
  ImGui.ImDrawListAddText(draw,start,y+(bh-labelH)*.5,textCol,label)
  return clicked,hovered,bw
end

local function categoryRailButton(id,label,kind,w,h,active)
  local x,y=ImGui.GetCursorScreenPos()
  local draw=ImGui.GetWindowDrawList()
  ImGui.InvisibleButton("##crb"..id,w,h)
  local hovered=ImGui.IsItemHovered()
  local clicked=ImGui.IsItemClicked()

  local fill
  if active then fill=dashU32({.11,.12,.08,1})
  elseif hovered then fill=dashU32({.045,.095,.110,1})
  else fill=dashU32({.020,.050,.063,1}) end

  local border=active and dashU32(C.yellow) or (hovered and dashU32(C.cyan) or dashU32(C.border))
  local textCol=active and dashU32(C.yellow) or dashU32(C.text)
  local glyphCol=dashU32(C.text)

  ImGui.ImDrawListAddRectFilled(draw,x,y,x+w,y+h,fill,3)
  ImGui.ImDrawListAddRect(draw,x,y,x+w,y+h,border,3,0,active and 1.7 or 1.3)

  local icon=safe(kindIcon(kind))
  local iconW,iconH=ImGui.CalcTextSize(icon)
  local labelW,labelH=ImGui.CalcTextSize(label)
  local iconX=x+14
  local labelX=x+42
  ImGui.ImDrawListAddText(draw,iconX,y+(h-iconH)*.5,glyphCol,icon)
  ImGui.ImDrawListAddText(draw,labelX,y+(h-labelH)*.5,textCol,label)

  return clicked,hovered
end

local function browseRecordRow(r,id,w,h)
  local x,y=ImGui.GetCursorScreenPos()
  local draw=ImGui.GetWindowDrawList()
  ImGui.InvisibleButton("##browrow"..id,w,h)
  local hovered=ImGui.IsItemHovered()
  local clicked=ImGui.IsItemClicked()

  local fill=hovered and dashU32({.035,.085,.10,1}) or dashU32({.014,.034,.043,1})
  local border=hovered and dashU32(C.cyan) or dashU32({.06,.22,.27,1})
  ImGui.ImDrawListAddRectFilled(draw,x,y,x+w,y+h,fill,2)
  ImGui.ImDrawListAddRect(draw,x,y,x+w,y+h,border,2,0,1.0)

  local icon=safe(kindIcon(r.kind))
  local iconW,iconH=ImGui.CalcTextSize(icon)
  local name=clampText(r.name or r.key,56)
  local nameW,nameH=ImGui.CalcTextSize(name)
  local typeW,typeH=ImGui.CalcTextSize(r.kind)

  ImGui.ImDrawListAddText(draw,x+10,y+(h-iconH)*.5,dashU32(C.text),icon)
  ImGui.ImDrawListAddText(draw,x+34,y+(h-nameH)*.5,dashU32(C.text),name)
  ImGui.ImDrawListAddText(draw,x+w-typeW-12,y+(h-typeH)*.5,dashU32(C.dim),r.kind)
  return clicked,hovered
end

local function relatedRecordButton(id,r,label,w,h)
  local bw=math.max(220,w or 220)
  local bh=math.max(30,h or 30)
  local rel=safe(label or r.kind)
  local relW,relH=ImGui.CalcTextSize(rel)

  local x,y=ImGui.GetCursorScreenPos()
  local draw=ImGui.GetWindowDrawList()
  ImGui.InvisibleButton("##relbtn"..id,bw,bh)
  local hovered=ImGui.IsItemHovered()
  local clicked=ImGui.IsItemClicked()

  local fill=hovered and dashU32({.040,.090,.105,1}) or dashU32({.020,.050,.063,1})
  local border=hovered and dashU32(C.cyan) or dashU32(C.border)
  ImGui.ImDrawListAddRectFilled(draw,x,y,x+bw,y+bh,fill,3)
  ImGui.ImDrawListAddRect(draw,x,y,x+bw,y+bh,border,3,0,1.3)

  local icon=safe(kindIcon(r.kind))
  local iconW,iconH=ImGui.CalcTextSize(icon)
  local name=safe(r.name or r.key)
  local maxNameW=math.max(40,bw-46-relW-34)
  while #name>4 and ImGui.CalcTextSize(name)>maxNameW do
    name=name:sub(1,#name-4).."..."
  end
  local nameW,nameH=ImGui.CalcTextSize(name)

  ImGui.ImDrawListAddText(draw,x+12,y+(bh-iconH)*.5,dashU32(C.text),icon)
  ImGui.ImDrawListAddText(draw,x+38,y+(bh-nameH)*.5,dashU32(C.text),name)
  ImGui.ImDrawListAddText(draw,x+bw-relW-12,y+(bh-relH)*.5,dashU32(C.dim),rel)
  return clicked,hovered
end

local function relatedRecords(r,limit)
  local out={}; local seen={}
  for _,rel in ipairs(r.related or {}) do
    local t=getByUid(rel.target)
    if t and not seen[t.uid] then
      out[#out+1]={r=t,label=rel.label}
      seen[t.uid]=true
      if limit and #out>=limit then break end
    end
  end
  return out
end

local function drawRelated(r)
  local rels=relatedRecords(r,80)
  if #rels==0 then tc(C.dim,"No indexed relationships for this record."); return end
  local cap=ImGui.GetContentRegionAvail()
  for i,x in ipairs(rels) do
    if relatedRecordButton("generic"..i..x.r.uid,x.r,x.label,cap,30) then openRecord(x.r) end
    ImGui.Spacing()
  end
end

local function drawRelatedButtons(r)
  local rels=relatedRecords(r,80)
  if #rels==0 then tc(C.dim,"No indexed relationships for this record."); return end
  local w=ImGui.GetContentRegionAvail()
  for i,x in ipairs(rels) do
    if relatedRecordButton("detailrel"..i..x.r.uid,x.r,x.label,w,30) then openRecord(x.r) end
    ImGui.Spacing()
  end
end

local function vectorResultRow(r,id,w,h,active)
  local x,y=ImGui.GetCursorScreenPos()
  local draw=ImGui.GetWindowDrawList()
  ImGui.InvisibleButton("##vrow"..id,w,h)
  local hovered=ImGui.IsItemHovered()
  local clicked=ImGui.IsItemClicked()

  if active or hovered then
    local fill=active and dashU32({.045,.19,.24,1}) or dashU32({.035,.085,.10,1})
    ImGui.ImDrawListAddRectFilled(draw,x,y,x+w,y+h,fill,2)
  end
  if active then
    ImGui.ImDrawListAddRect(draw,x,y,x+w,y+h,dashU32(C.cyan),2,0,1.5)
  end

  drawVectorIcon(draw,r.kind,x+13,y+h*.5,18,(r.kind=="Reward" or r.kind=="Achievement" or r.kind=="Scene" or r.kind=="Quest Phase") and C.yellow or C.text)
  ImGui.ImDrawListAddText(draw,x+30,y+(h-17)*.5,dashU32(C.text),clampText(r.name or r.key,46))
  local typeW,typeH=ImGui.CalcTextSize(r.kind)
  ImGui.ImDrawListAddText(draw,x+w-typeW-8,y+(h-typeH)*.5,dashU32(C.dim),r.kind)
  return clicked,hovered
end

local function homePage()
  local avail=ImGui.GetContentRegionAvail()
  local baseX,baseY=ImGui.GetCursorScreenPos()

  -- One rectangular dashboard silhouette: 3 hero cards exactly match the
  -- width of the 4-card grid below.
  local tileW=160
  local gap=6
  local tileTotal=tileW*4+gap*3
  local heroW=(tileTotal-gap*2)/3
  local heroH=126
  local tileH=124
  local dashStart=math.max(0,(avail-tileTotal)*.5)

  local function tileAt(x,y,...)
    ImGui.SetCursorScreenPos(x,y)
    dashboardTile(...)
  end

  local hy=baseY+6
  tileAt(baseX+dashStart,hy,"heroBrowse","browse","Browse The Game","Explore all game data","by category",heroW,heroH,C.cyan,function()
    browseTab=1; go(BROWSE)
  end,36)
  tileAt(baseX+dashStart+heroW+gap,hy,"heroContext","context","Current Context","See what's active","in your session",heroW,heroH,C.cyan,function()
    if selected then openRecord(selected)
    else statusDetail="Open a record first; Current Context returns to the most recently selected record." end
  end,36)
  tileAt(baseX+dashStart+(heroW+gap)*2,hy,"heroRecent","recent","Recent Changes","Track updates and","recent activity",heroW,heroH,C.cyan,function()
    browseTab=3; go(BROWSE)
  end,36)

  local desc={
    Quests={"Story and side","content"}, Facts={"Game state","variables"},
    Journal={"Entries and","objectives"}, Items={"Weapons, gear","and more"},
    Rewards={"Items and","grants"}, Achievements={"Progression and","conditions"},
    Scenes={"Scene resources","and sequences"}, ["Quest Phases"]={"Logic, nodes","and conditions"}
  }

  local catY=hy+heroH+gap
  for i,cat in ipairs(categories) do
    local col=(i-1)%4
    local row=math.floor((i-1)/4)
    local kind=kindFromCategory(cat)
    local d=desc[cat] or {"",""}
    local tx=baseX+dashStart+col*(tileW+gap)
    local ty=catY+row*(tileH+gap)
    tileAt(tx,ty,"cat"..i,kind,cat,d[1],d[2],tileW,tileH,(i>=5) and C.yellow or C.text,function()
      currentCategory=cat; listFilter=""; go(LIST)
    end,28)
  end

  local bottom=catY+tileH*2+gap
  ImGui.SetCursorScreenPos(baseX,bottom+7)
  sep()

  -- Mockup-style utility row: two compact controls, status beneath.
  if vectorControlButton("homeSearch","SEARCH","search",110,30,false,C.cyan) then
    searchTab=SEARCH_INPUT
    searchFocusRequested=true
    go(SEARCH)
  end
  ImGui.SameLine()
  local refreshLabel=indexBuilt and "REFRESH" or "BUILD INDEX"
  if vectorControlButton("homeRefresh",refreshLabel,"recent",120,30,false,C.cyan) then
    buildQueued=true
    statusText="QUEUED"
    statusDetail="Index build queued for the game update loop."
  end

  ImGui.Spacing()
  tc(indexBuilt and C.green or C.dim,indexBuilt and ("INDEX READY  "..#records.." RECORDS") or (indexing and "INDEXING..." or "INDEX NOT BUILT"))
  if indexing then ImGui.ProgressBar(buildProgress,-1,16) end
  if lastError~="" then tc(C.red,"Index note: "..clampText(lastError,110)) end

  componentLine()

  if liveSessionAttached then
    tc(C.green,string.format("LIVE SAVE ATTACHED  Facts %d  Journal %d  Active %d  Succeeded %d  Failed %d",
      liveStats.facts,liveStats.journal,liveStats.active,liveStats.succeeded,liveStats.failed))
  else
    tc(C.dim,"LIVE SAVE STATE: waiting for a playable session")
  end

  if indexBuilt then
    tc(C.dim,string.format("Quests %d  Facts %d  Journal %d  Items %d  Rewards %d  Achievements %d  Scenes %d  Quest Phases %d",
      #(byKind["Quest"] or {}), #(byKind["Fact"] or {}), #(byKind["Journal"] or {}), #(byKind["Item"] or {}),
      #(byKind["Reward"] or {}), #(byKind["Achievement"] or {}), #(byKind["Scene"] or {}), #(byKind["Quest Phase"] or {})))
  end
end
local function helpPage()
  -- One scrollable Help page; no secondary navigation controls.
  local function heading(s)
    ImGui.Spacing(); tc(C.yellow,s); ImGui.Separator(); ImGui.Spacing()
  end
  local function subheading(s)
    ImGui.Spacing(); tc(C.cyan,s); ImGui.Spacing()
  end
  local function paragraph(s)
    ImGui.TextWrapped(s); ImGui.Spacing()
  end
  tc(C.yellow,"CP2077 WIRE ATLAS")
  tc(C.dim,"HELP & FEATURE REFERENCE  |  v0.3.39")
  ImGui.Spacing()
  heading("1. WHAT WIRE ATLAS DOES")
  paragraph("Wire Atlas provides a read-only view into Cyberpunk 2077 internal records and the relationships between them. It combines information exposed by the running game with previously researched references, allowing modders to investigate quest states, journal structures, game facts, equipment definitions, and known logic connections.")
  paragraph("Its value is bringing several game systems into one searchable interface. Researchers can follow related records, identify known sources of state changes, and distinguish documented connections from broader associations.")
  paragraph("It does not claim to reconstruct every dependency in the game. It presents information available through its runtime readers and verified research data.")
  heading("2. HOME DASHBOARD")
  paragraph("The Home dashboard brings together research features, indexed data collections, component diagnostics, and live-session information.")
  subheading("PRIMARY RESEARCH FEATURES")
  paragraph("Browse The Game provides records organized by game-data category, useful when exploring without a known identifier.")
  paragraph("Current Context returns to the record selected within Wire Atlas, not necessarily V currently tracked quest.")
  paragraph("Recent Changes shows previously opened records. Despite its label, this is research navigation history, not a log of changes to game state.")
  subheading("THE EIGHT DATA COLLECTIONS")
  paragraph("Each collection represents a different kind of internal game information. Separating them helps distinguish records that may be related but serve different purposes.")
  paragraph("Quests - Quest identifiers derived from journal information, with links to associated journal entries. Useful for exploring quest and journal structures.")
  paragraph("Facts - Named numeric values from the quest system. They can represent decisions, progression markers, conditions, or outcomes. Their meaning depends on the game logic using them; zero has no universal interpretation.")
  paragraph("Journal - Entries and objectives with available paths, identifiers, hashes, hierarchy, and progression states. An individual objective state is not necessarily the entire quest state.")
  paragraph("Items - TweakDB definitions for supported weapons, cyberware, clothing, and consumables. These are definitions, not V current inventory.")
  paragraph("Rewards - Reward-related definitions exposed through supported TweakDB record types. A definition does not establish that a reward was granted.")
  paragraph("Achievements - TweakDB achievement definitions, not a list of achievements unlocked by the player.")
  paragraph("Scenes - Known scene resources identified through researched references. They can connect documented state changes to source resources; this is not a complete scene inventory.")
  paragraph("Quest Phases - Known quest-phase resources associated with researched logic references, not every node or condition in the shipped quest-phase files.")
  subheading("INDEX MANAGEMENT AND REFRESH")
  paragraph("Wire Atlas automatically builds its initial index during initialization. BUILD INDEX appears before an index exists; afterward the control becomes REFRESH.")
  paragraph("Refresh reconstructs the indexed collection: seeds verified identifiers, reads available facts through QuestsSystem, walks JournalManager entries, enumerates supported TweakDB records, generates relationships from matching quest identifiers, and applies researched writer, reader, and source relationships.")
  paragraph("These steps provide different levels of evidence. A relationship inferred from a shared quest identifier is not equivalent to a writer or reader established through resource research.")
  paragraph("Refresh is useful when a fresh index is needed after changes to the game session. It does not modify game state.")
  subheading("INDEX STATUS AND COLLECTION STATISTICS")
  paragraph("QUEUED - An index rebuild has been requested.")
  paragraph("INDEXING - Wire Atlas is constructing the index.")
  paragraph("READY - An indexed collection is available.")
  paragraph("LIVE - A playable session was detected and live values were refreshed.")
  paragraph("ERROR - The build did not produce a usable index.")
  paragraph("INDEX READY and its record count report how many records Wire Atlas currently stores. Category totals show their distribution among Quests, Facts, Journal, Items, Rewards, Achievements, Scenes, and Quest Phases.")
  paragraph("These are collection statistics, not completion statistics. They describe inspection coverage, not how many quests V completed or how many resources exist in the game. A large Journal collection and small Scenes collection reflect different collection methods, not the total number of scenes in Cyberpunk 2077.")
  paragraph("An Index note reports a problem in an individual reader. Other indexed records may remain usable when one stage fails.")
  subheading("COMPONENT DIAGNOSTICS")
  paragraph("REDscript OK / missing indicates whether the Wire Atlas REDscript bridge responded to its version probe.")
  paragraph("Native OK / missing indicates whether the native marker was detected. The native component registers its REDscript support through RED4ext.")
  paragraph("Codeware class count, when available, reports the reflection class count returned through the bridge. It is not an indexed-record count, performance measurement, or quest-progression statistic.")
  paragraph("These are detection indicators, not comprehensive tests of every component function.")
  subheading("LIVE SAVE INFORMATION")
  paragraph("Wire Atlas can build an index at the main menu before a playable save is attached. On entering a playable session, it refreshes supported live FactsDB values and JournalManager states.")
  paragraph("LIVE SAVE ATTACHED reports five statistics:")
  paragraph("Facts - Indexed fact records successfully refreshed through the live quest system.")
  paragraph("Journal - Indexed journal entries whose states were successfully refreshed.")
  paragraph("Active - Refreshed journal entries reporting Active.")
  paragraph("Succeeded - Refreshed journal entries reporting Succeeded.")
  paragraph("Failed - Refreshed journal entries reporting Failed.")
  paragraph("Inactive entries can appear in the Journal total without appearing in those three state subtotals. These values indicate refreshed coverage and state distribution, not the player total completed quests or achievements.")
  paragraph("Live values refresh on playable-session attachment or index rebuild during play. Wire Atlas does not continuously poll every indexed fact and journal entry each frame.")
  heading("3. BROWSE - RECORDS AND RESEARCH TOOLS")
  paragraph("Browse organizes the index into Categories, All Items, and Recent, with shortcuts to specialized inspection features.")
  subheading("CATEGORIES")
  paragraph("The eight collections separate records by type. Each displays its record count and a list filter that examines names, identifiers, and available paths. Lists show up to 500 matching records; this display limit does not restrict the index.")
  subheading("ALL ITEMS")
  paragraph("All Items combines records across categories in pages of 200. OPEN RECORD opens the appropriate inspector; OPEN RELATIONSHIP GRAPH opens the graph centered on that record. The combined view is useful for cross-system investigation.")
  subheading("RECENT")
  paragraph("Recent maintains a session-level history of previously opened records, consolidating repeated entries. It is navigation history, not a game-state change log.")
  subheading("ADDITIONAL RESEARCH FEATURES")
  paragraph("Writers / Readers - Known sources that modify, inspect, or reference indexed records.")
  paragraph("Relationship Graph - Visual inspection of record connections.")
  paragraph("Relationships - Associated records and relationship labels.")
  paragraph("Raw Data - Information retained in the index for a selected record.")
  paragraph("Conditions - Available source and relationship information for Items and Rewards.")
  paragraph("Record Inspector - Detailed information about a selected record.")
  paragraph("Current Context - The current research selection.")
  paragraph("These are entry points into the existing index, not separate collections. Some shortcuts select a suitable indexed record when the current selection is unavailable or incompatible.")
  heading("4. SEARCH - IDENTIFIERS AND GAME-STATE VALUES")
  paragraph("Search finds records by identifier, name, path, and source description. Exact identifier matches receive priority, followed by other matches ordered by type and name. Up to 300 results are displayed.")
  paragraph("The preview shows available identifier, type, value or journal state, path, and counts of relationships, writers, and readers. These counts describe what Wire Atlas currently knows, not every connection in the game.")
  subheading("DIRECT FACT LOOKUP")
  paragraph("Search can request a named fact directly from QuestsSystem even if it was not in the initial index. A successful lookup can add the fact to the current session records.")
  paragraph("This is useful for identifiers discovered through outside research or resource inspection. A returned value establishes what the fact reader reported; significance depends on the game logic using it.")
  paragraph("An absent search result does not establish that a record is absent from Cyberpunk 2077; it may simply be outside the current index.")
  heading("5. RECORD INSPECTOR - UNDERSTANDING AN ENTRY")
  paragraph("The Record Inspector brings together available evidence for an individual record.")
  paragraph("Overview identifies the record type, internal identifier, source, metadata, and selected related records.")
  paragraph("Relationships displays indexed connections and supports navigation between associated entries.")
  paragraph("Raw Data exposes the fields Wire Atlas retained during indexing; it is not necessarily every property of the original engine object.")
  paragraph("The Source field helps distinguish runtime records from verified research entries. Writers / Readers and Relationship Graph provide further relationship analysis.")
  heading("6. WRITERS / READERS - TRACING KNOWN SOURCES")
  paragraph("Writers identify documented sources that set or modify a record. Readers identify sources that check or reference it. Related displays associated indexed records.")
  paragraph("Source annotations may include scene or quest-phase filenames, node references, and recorded operations, such as a node associated with setting a particular fact.")
  paragraph("This information helps investigate where a state originates or which known resources depend on it. It comes from research included with Wire Atlas, not an exhaustive automatic trace of every game read or write.")
  paragraph("An empty list means no proven source entry is available in the current index, not that the game contains no such source.")
  heading("7. RELATIONSHIP GRAPH - FOLLOWING GAME LOGIC")
  paragraph("The graph presents the immediate indexed connections around a selected record, rather than displaying an entire quest. Incoming connections appear on the left, the selected record in the center, and outgoing connections on the right.")
  subheading("NODES")
  paragraph("The center node displays available identifiers, source, path, state or value, and writer/reader counts. Neighbors show identifying information and their relationship to the selected record.")
  paragraph("Node colors distinguish types: Quest - green; Fact - yellow; Journal - cyan; Scene - blue; Quest Phase - purple; Reward - orange; Item - light gray; Achievement - gold. The inline legend identifies the primary types.")
  subheading("WIRES AND RELATIONSHIP DIRECTION")
  paragraph("Directional wires connect record sockets. Hover information includes source, destination, relationship label, and available supporting annotations.")
  paragraph("A wire can represent a writer, reader, journal relationship, or another indexed association. Selecting an indexed neighbor or following its wire recenters the graph on that record, allowing one-step investigation.")
  paragraph("Some researched source references are visible without an independently indexed destination. They provide evidence but cannot open a full record.")
  subheading("VIEWPORT CONTROLS")
  paragraph("RESET restores the default graph scroll position. FIT VIEW centers the selected record while retaining readable card dimensions. Scrolling accommodates larger one-hop neighborhoods.")
  subheading("INTERPRETING RELATIONSHIPS")
  paragraph("Parent/child can describe journal hierarchy; quest association can indicate a shared quest reference; writer and reader connections identify researched sources that change or check records.")
  paragraph("Shared identifiers or structural relationships do not by themselves prove execution order. The graph represents supported connections, not a complete reconstruction of every condition, branch, or execution path. Graph export is not currently enabled.")
  heading("8. JOURNAL INSPECTOR - STATES AND HIERARCHY")
  paragraph("Tree displays available parent and child entries from JournalManager. Entry displays path, identifier, hash, current state, and known writer count. Related displays associated indexed records.")
  paragraph("Inactive - The entry is not currently active. Active - The entry is currently active. Succeeded - The entry reports success. Failed - The entry reports failure.")
  paragraph("These states belong to individual entries. A succeeded objective does not necessarily mean the entire quest is complete. Journal hierarchy is not execution order: parent and child structure does not establish the sequence of condition evaluation.")
  paragraph("The inspector links to Writers / Readers and Relationship Graph for additional evidence.")
  heading("9. ITEM AND REWARD INSPECTOR - DEFINITIONS AND CONDITIONS")
  paragraph("Overview displays identifier, source, record type, and associated records. Conditions displays known source information when supported by the index, not every prerequisite for acquiring an item or reward. Related displays connections to other indexed records.")
  paragraph("Wire Atlas attempts to resolve readable item names and TweakDB identifiers through game methods. Some entries retain internal identifiers when a readable name cannot be resolved.")
  paragraph("A definition is not an acquired item. Its presence in TweakDB does not establish that V owns it, was awarded it, or can obtain it in the current game state.")
  heading("10. DATA SOURCES AND RESEARCH COVERAGE")
  subheading("QUESTSSYSTEM AND FACTSDB")
  paragraph("Provide named game-state facts and available numeric values. Their meaning depends on the game logic that uses them.")
  subheading("JOURNALMANAGER")
  paragraph("Provides journal entries, identifiers, hashes, hierarchy, and available progression states.")
  subheading("TWEAKDB")
  paragraph("Provides supported Item, Reward, and Achievement definitions, not player ownership or completion.")
  subheading("VERIFIED RESEARCH REFERENCES")
  paragraph("Supply researched fact identifiers, scene and quest-phase references, writer/reader descriptions, and known relationships supplementing runtime information.")
  subheading("REDSCRIPT, RED4EXT, AND CODEWARE")
  paragraph("The REDscript bridge provides version identification and reflection helpers, including class and global-function counts and a resource-existence helper. The native component registers REDscript support through RED4ext and provides a detection marker.")
  paragraph("These components support integration and diagnostics; their presence does not mean every game resource is indexed.")
  subheading("UNDERSTANDING COVERAGE")
  paragraph("Collection totals describe records Wire Atlas currently indexes, not all records in Cyberpunk 2077. Runtime records, researched references, and identifier-based associations have different evidentiary strengths and are not interchangeable proof of execution behavior.")
  heading("11. READ-ONLY SCOPE")
  paragraph("Wire Atlas is designed for inspecting game information without changing underlying game state. Its research functions do not intentionally modify quest facts, journal states, inventory, reward ownership, achievements, TweakDB definitions, or saved games.")
  paragraph("Its purpose is to make existing information accessible, searchable, and easier to investigate.")
end
local function browseFeatureCard(id,title,desc1,desc2,icon,w,h,onClick)
  browseGridCard(
    "feature"..id,
    icon,
    title,
    desc1,
    desc2,
    w,
    h or 86,
    onClick
  )
end

local function firstIndexedRecord()
  return records[1]
end

local function firstRecordWithRelations()
  for _,r in ipairs(records) do
    if r and #(r.related or {})>0 then return r end
  end
  return nil
end

local function firstGraphCompatibleRecord()
  return firstRecordWithRelations() or firstIndexedRecord()
end

local function firstConditionsRecord()
  for _,kind in ipairs({"Item","Reward"}) do
    for _,r in ipairs(byKind[kind] or {}) do
      if r and (#(r.writers or {})>0 or #(r.related or {})>0) then return r end
    end
  end
  for _,kind in ipairs({"Item","Reward"}) do
    local arr=byKind[kind] or {}
    if arr[1] then return arr[1] end
  end
  return nil
end

local function ensureSelectedFor(feature)
  if feature=="conditions" then
    if selected and (selected.kind=="Item" or selected.kind=="Reward") then return selected end
    selected=firstConditionsRecord()
    return selected
  elseif feature=="relationships" or feature=="graph" or feature=="graph_tools" then
    if selected and #(selected.related or {})>0 then return selected end
    selected=firstRecordWithRelations() or firstIndexedRecord()
    return selected
  else
    if selected then return selected end
    selected=firstIndexedRecord()
    return selected
  end
end

local function allItemsRow(r,rowNum)
  local avail=ImGui.GetContentRegionAvail()
  local rowH=36
  local openW=170
  local graphW=260
  local gap=8
  local rightPad=0
  local x,y=ImGui.GetCursorScreenPos()
  local draw=ImGui.GetWindowDrawList()

  -- Non-clickable visual row shell.
  ImGui.ImDrawListAddRectFilled(draw,x,y,x+avail,y+rowH,dashU32({.014,.034,.043,1}),2)
  ImGui.ImDrawListAddRect(draw,x,y,x+avail,y+rowH,dashU32({.06,.22,.27,1}),2,0,1.0)

  local numText=tostring(rowNum).."."
  local numW,numH=ImGui.CalcTextSize(numText)
  local icon=safe(kindIcon(r.kind))
  local iconW,iconH=ImGui.CalcTextSize(icon)
  local kindText=safe(r.kind)
  local kindW,kindH=ImGui.CalcTextSize(kindText)

  -- Fixed left anchor: numbers begin at the same X and grow to the right.
  local numX=x+10
  local numGap=ImGui.CalcTextSize("  ")
  local iconX=numX+numW+numGap
  local nameX=iconX+28

  -- Right zone: text-only action buttons pinned to the right edge.
  local buttonsStart=x+avail-rightPad-openW-gap-graphW
  local kindX=buttonsStart-kindW-18

  local maxNameW=math.max(40,kindX-nameX-18)
  local name=safe(r.name or r.key)
  if ImGui.CalcTextSize(name)>maxNameW then
    local base=name
    while #base>4 and ImGui.CalcTextSize(base.."...")>maxNameW do
      base=base:sub(1,#base-1)
    end
    name=base.."..."
  end
  local nameW,nameH=ImGui.CalcTextSize(name)

  ImGui.ImDrawListAddText(draw,numX,y+(rowH-numH)*.5,dashU32(C.dim),numText)
  ImGui.ImDrawListAddText(draw,iconX,y+(rowH-iconH)*.5,dashU32(C.text),icon)
  ImGui.ImDrawListAddText(draw,nameX,y+(rowH-nameH)*.5,dashU32(C.text),name)

  -- Leave the existing middle type identifier unchanged.
  ImGui.ImDrawListAddText(draw,kindX,y+(rowH-kindH)*.5,dashU32(C.dim),kindText)

  -- Text-only action buttons.
  ImGui.SetCursorScreenPos(buttonsStart,y+2)
  if ImGui.Button("OPEN RECORD##allOpen"..rowNum..r.uid,openW,rowH-4) then
    openRecord(r)
  end

  ImGui.SameLine()
  if ImGui.Button("OPEN RELATIONSHIP GRAPH##allGraph"..rowNum..r.uid,graphW,rowH-4) then
    graphTab=GRAPH_MAIN
    go(GRAPH,r)
  end

  ImGui.SetCursorScreenPos(x,y+rowH)
  ImGui.Dummy(1,1)
  ImGui.Spacing()
end

local function browsePage()
  breadcrumb({"Browse"})
  subTabs({"CATEGORIES","ALL ITEMS","RECENT"},browseTab,function(v) browseTab=v end)

  if browseTab==1 then
    local avail=ImGui.GetContentRegionAvail()
    local w=(avail-21)/4

    -- Locked first 8 cards.
    for i,cat in ipairs(categories) do
      if ((i-1)%4)>0 then ImGui.SameLine() end
      categoryCard(cat,100+i,w,86)
    end

    -- Continue the exact same card run with 10 more cards.
    -- Unique icons only: none reused from the top 8 or from each other.
    local featureIcons = {
      G.AccountMultiple or G.AccountGroup or "WR",
      G.ChartTimelineVariant or G.VectorPolyline or "RG",
      G.LinkVariant or G.Link or "RL",
      G.CodeBraces or G.CodeTags or "RD",
      G.CheckCircleOutline or G.Check or "CN",
      G.MagnifyScan or G.Magnify or "RI",
      G.CrosshairsGps or G.Crosshairs or G.Target or "CC"
    }

    local function feature(i,title,d1,d2,action)
      local absoluteIndex=8+i
      if ((absoluteIndex-1)%4)>0 then ImGui.SameLine() end
      browseFeatureCard(i,title,d1,d2,featureIcons[i],w,86,action)
    end

    feature(1,"Writers / Readers","Inspect proven writers","and readers",function()
      local r=ensureSelectedFor("writers")
      if r then go(WRITERS,r) else statusDetail="No compatible indexed record is available." end
    end)

    feature(2,"Relationship Graph","Walk indexed links","visually",function()
      local r=ensureSelectedFor("graph")
      if r then graphTab=GRAPH_MAIN; go(GRAPH,r) else statusDetail="No graph-compatible indexed record is available." end
    end)

    feature(3,"Relationships","Open related-record","list",function()
      local r=ensureSelectedFor("relationships")
      if r then detailTab=DETAIL_REL; go(DETAIL,r) else statusDetail="No record with indexed relationships is available." end
    end)

    feature(4,"Raw Data","Inspect raw indexed","record data",function()
      local r=ensureSelectedFor("raw")
      if r then detailTab=DETAIL_RAW; go(DETAIL,r) else statusDetail="No indexed record is available." end
    end)


    feature(5,"Conditions","Inspect item / reward","conditions",function()
      local r=ensureSelectedFor("conditions")
      if r then itemTab=ITEM_CONDITIONS; go(ITEM,r) else statusDetail="No compatible Item or Reward record is available." end
    end)

    feature(6,"Record Inspector","Open selected record","overview",function()
      local r=ensureSelectedFor("record")
      if r then detailTab=DETAIL_OVERVIEW; go(DETAIL,r) else statusDetail="No indexed record is available." end
    end)



    local ctx1=selected and "Open selected record" or "Open most recently"
    local ctx2=selected and "context" or "selected record"
    feature(7,"Current Context",ctx1,ctx2,function()
      local r=ensureSelectedFor("context")
      if r then openRecord(r) else statusDetail="No indexed record is available." end
    end)

  elseif browseTab==2 then
    local total=#records
    if total==0 then
      tc(C.dim,indexBuilt and "No indexed records." or "Build the index from Home first.")
    else
      local totalPages=math.max(1,math.ceil(total/ALL_ITEMS_PAGE_SIZE))
      if allItemsPage<1 then allItemsPage=1 end
      if allItemsPage>totalPages then allItemsPage=totalPages end

      local startIndex=(allItemsPage-1)*ALL_ITEMS_PAGE_SIZE+1
      local endIndex=math.min(total,startIndex+ALL_ITEMS_PAGE_SIZE-1)

      for i=startIndex,endIndex do
        allItemsRow(records[i],i)
      end

      -- Pagination replaces the old truncation message and appears at page bottom.
      ImGui.Spacing()
      tc(C.dim,string.format("Showing %d-%d of %d records",startIndex,endIndex,total))
      ImGui.Spacing()

      local groupStart=math.floor((allItemsPage-1)/5)*5+1
      local groupEnd=math.min(totalPages,groupStart+4)

      -- Slightly taller buttons provide balanced bottom padding.
      local pagerH=32
      if ImGui.Button("BACK##allItemsBack",78,pagerH) and allItemsPage>1 then
        allItemsPage=allItemsPage-1
      end
      for p=groupStart,groupEnd do
        ImGui.SameLine()
        if p==allItemsPage then
          ImGui.PushStyleColor(ImGuiCol.Button,.10,.12,.10,1)
          ImGui.PushStyleColor(ImGuiCol.Text,table.unpack(C.yellow))
        end
        if ImGui.Button(tostring(p).."##allItemsPage"..p,42,pagerH) then
          allItemsPage=p
        end
        if p==allItemsPage then ImGui.PopStyleColor(2) end
      end
      ImGui.SameLine()
      if ImGui.Button("NEXT##allItemsNext",78,pagerH) and allItemsPage<totalPages then
        allItemsPage=allItemsPage+1
      end
    end

  else
    tc(C.dim,"Recent opens")
    local shown={}
    for i=#selectedHistory,1,-1 do
      local uid=selectedHistory[i]
      if not shown[uid] then
        local r=getByUid(uid)
        if r then recordButton(r,3000+i); shown[uid]=true end
      end
    end
    if next(shown)==nil then tc(C.dim,"No records opened yet.") end
  end
end

local function listPage()
  breadcrumb({"Browse",currentCategory})
  local kind=kindFromCategory(currentCategory)
  local list=byKind[kind] or {}

  ImGui.BeginChild("ListFilters",220,0,true)

  -- Current category header uses the same glyph source as Browse overview.
  local icon=kindIcon(kind)
  tc(C.text,icon)
  ImGui.SameLine()
  tc(C.yellow,currentCategory:upper())
  sep()

  local changed,new=inputText("Search...##list",listFilter,128)
  if changed then listFilter=new end

  -- One divider only under the current-category block.
  tc(C.dim,"CATEGORIES")
  ImGui.Spacing()

  local railW=ImGui.GetContentRegionAvail()
  for i,cat in ipairs(categories) do
    local k=kindFromCategory(cat)
    local active=(cat==currentCategory)
    if categoryRailButton("sidecat"..i,cat,k,railW,30,active) then
      currentCategory=cat
      listFilter=""
    end
    ImGui.Spacing()
  end
  ImGui.EndChild()

  ImGui.SameLine()
  ImGui.BeginChild("ListRecords",0,0,true)
  local listIcon=kindIcon(kind)
  tc(C.text,listIcon)
  ImGui.SameLine()
  tc(C.yellow,currentCategory.."  "..#list)
  ImGui.Separator()

  local shown=0
  local rowW=ImGui.GetContentRegionAvail()
  for i,r in ipairs(list) do
    if contains(r.name,listFilter) or contains(r.key,listFilter) or contains(r.path,listFilter) then
      if browseRecordRow(r,"list"..i,rowW-8,30) then openRecord(r) end
      ImGui.Spacing()
      shown=shown+1
    end
    if shown>=500 then tc(C.dim,"Showing first 500 matches. Refine Search to narrow the list."); break end
  end
  if shown==0 then tc(C.dim,indexBuilt and "No matching indexed records." or "Build the index from Home first.") end
  ImGui.EndChild()
end

local function searchPage()
  breadcrumb({"Search"})

  tc(C.dim,"SEARCH TERM")
  if searchFocusRequested then ImGui.SetKeyboardFocusHere(); searchFocusRequested=false end

  ImGui.PushItemWidth(470)
  ImGui.PushStyleColor(ImGuiCol.FrameBg,.025,.055,.070,1)
  ImGui.PushStyleColor(ImGuiCol.FrameBgHovered,.040,.085,.100,1)
  ImGui.PushStyleColor(ImGuiCol.FrameBgActive,.055,.105,.120,1)
  ImGui.PushStyleColor(ImGuiCol.Border,.08,.42,.52,1)
  local newText,changed=ImGui.InputText("##searchInput",searchText,256)
  ImGui.PopStyleColor(4)
  ImGui.PopItemWidth()
  if changed then searchText=newText; searchHasRun=false end

  local enterPressed=false
  local okEnter,valEnter=pcall(function() return ImGui.IsKeyPressed(ImGuiKey.Enter) end)
  if okEnter and valEnter then enterPressed=true end

  ImGui.SameLine()
  local runClicked=vectorControlButton("searchRun","SEARCH","search",112,28,false,C.cyan)
  if runClicked or enterPressed then
    doSearch(searchText)
    searchHasRun=true
  end

  local filtered={}
  for _,r in ipairs(searchResults) do filtered[#filtered+1]=r end

  if not searchHasRun then
    ImGui.Spacing()
    tc(C.yellow,"SEARCH THE INDEX")
    ImGui.TextWrapped("Search identifiers, names, journal paths, sources, items, rewards, achievements and facts.")
    return
  end

  ImGui.Spacing()
  local listW=440
  ImGui.BeginChild("SearchList",listW,0,true)
  tc(C.yellow,"RESULTS  "..#filtered)
  ImGui.Separator()

  local shown=0
  for i,r in ipairs(filtered) do
    if shown>=300 then tc(C.dim,"Showing first 300 results. Refine the search."); break end
    local active=selected and selected.uid==r.uid
    if vectorResultRow(r,"sr"..i,listW-18,30,active) then selected=r end
    shown=shown+1
  end
  if #filtered==0 then
    tc(C.dim,'No matches found for "'..safe(searchText)..'".')
  end
  ImGui.EndChild()

  ImGui.SameLine()
  ImGui.BeginChild("SearchPreview",0,0,true)
  if selected then
    local px,py=ImGui.GetCursorScreenPos()
    drawVectorIcon(ImGui.GetWindowDrawList(),selected.kind,px+15,py+15,24,(selected.kind=="Reward" or selected.kind=="Achievement" or selected.kind=="Scene" or selected.kind=="Quest Phase") and C.yellow or C.text)
    ImGui.SetCursorPosX(ImGui.GetCursorPosX()+34)
    tc(C.yellow,selected.name)
    ImGui.SetCursorPosX(ImGui.GetCursorPosX()+34)
    tc(C.cyan,selected.kind)
    sep()
    ImGui.TextWrapped("Identifier: "..safe(selected.key))
    if selected.value~=nil then tc(C.green,"Current Value: "..safe(selected.value)) end
    if selected.state then tc(stateColor(selected.state),"State: "..selected.state) end
    if selected.path then ImGui.TextWrapped("Path: "..selected.path) end
    ImGui.Spacing()
    tc(C.dim,"Related: "..#(selected.related or {}).."   Writers: "..#(selected.writers or {}).."   Readers: "..#(selected.readers or {}))
    if vectorControlButton("fullDetails","VIEW FULL DETAILS","Quest Phase",ImGui.GetContentRegionAvail(),34,false,C.cyan) then openRecord(selected) end
  else
    tc(C.dim,#filtered>0 and "Select a result to preview it." or "No result selected.")
  end
  ImGui.EndChild()
end

local function detailPage()
  if not selected then tc(C.dim,"No record selected."); return end
  breadcrumb({"Search","Results",selected.name})

  local avail=ImGui.GetContentRegionAvail()
  local tw=(avail-12)/3
  if vectorControlButton("dtOverview","OVERVIEW","Quest",tw,30,detailTab==DETAIL_OVERVIEW,C.cyan) then detailTab=DETAIL_OVERVIEW end
  ImGui.SameLine()
  if vectorControlButton("dtRelationships","RELATIONSHIPS","Quest Phase",tw,30,detailTab==DETAIL_REL,C.cyan) then detailTab=DETAIL_REL end
  ImGui.SameLine()
  if vectorControlButton("dtRaw","RAW DATA","Fact",tw,30,detailTab==DETAIL_RAW,C.cyan) then detailTab=DETAIL_RAW end

  local actionW=(avail-6)/2
  if vectorControlButton("dWriters","WRITERS / READERS","context",actionW,30,false,C.cyan) then go(WRITERS,selected) end
  ImGui.SameLine()
  if vectorControlButton("dGraph","RELATIONSHIP GRAPH","Quest Phase",actionW,30,false,C.cyan) then go(GRAPH,selected) end
  sep()

  local hx,hy=ImGui.GetCursorScreenPos()
  drawVectorIcon(ImGui.GetWindowDrawList(),selected.kind,hx+14,hy+14,24,(selected.kind=="Reward" or selected.kind=="Achievement" or selected.kind=="Scene" or selected.kind=="Quest Phase") and C.yellow or C.text)
  ImGui.SetCursorPosX(ImGui.GetCursorPosX()+34)
  tc(C.yellow,selected.name)
  ImGui.SetCursorPosX(ImGui.GetCursorPosX()+34)
  tc(C.cyan,selected.kind)
  if selected.value~=nil then ImGui.SameLine(); tc(C.green,"  Current Value: "..safe(selected.value)) end
  if selected.state then ImGui.SameLine(); tc(stateColor(selected.state),"  "..selected.state) end
  sep()

  if detailTab==DETAIL_OVERVIEW then
    ImGui.Columns(2,"DetailCols",true)
    ImGui.Text("Identifier"); ImGui.NextColumn(); tc(C.cyan,safe(selected.key)); ImGui.NextColumn()
    ImGui.Text("Type"); ImGui.NextColumn(); ImGui.Text(selected.kind); ImGui.NextColumn()
    ImGui.Text("Source"); ImGui.NextColumn(); ImGui.TextWrapped(safe(selected.source)); ImGui.NextColumn()
    if selected.recordType then ImGui.Text("Record Type"); ImGui.NextColumn(); ImGui.TextWrapped(selected.recordType); ImGui.NextColumn() end
    if selected.path then ImGui.Text("Path"); ImGui.NextColumn(); ImGui.TextWrapped(selected.path); ImGui.NextColumn() end
    ImGui.Columns(1)

    sep()
    local rels=relatedRecords(selected,8)
    tc(C.yellow,"RELATED")
    ImGui.Spacing()
    local rw=ImGui.GetContentRegionAvail()
    for i,x in ipairs(rels) do
      if relatedRecordButton("overview"..i..x.r.uid,x.r,x.label,rw,30) then openRecord(x.r) end
      ImGui.Spacing()
    end
    if #rels==0 then tc(C.dim,"No indexed relationships.") end

  elseif detailTab==DETAIL_REL then
    drawRelatedButtons(selected)
  else
    for k,v in pairs(selected.raw or {}) do ImGui.TextWrapped(safe(k)..": "..safe(v)) end
  end
end

local function writersPage()
  if not selected then tc(C.dim,"No record selected."); return end
  breadcrumb({selected.kind,selected.name,"Writers / Readers"})
  subTabs({"WRITERS","READERS","RELATED"},wrTab,function(v) wrTab=v end)

  tc(C.yellow,kindIcon(selected.kind).."  "..selected.name)
  if selected.value~=nil then ImGui.SameLine(); tc(C.green,"  "..safe(selected.value)) end
  sep()

  if wrTab==WR_RELATED then drawRelated(selected); return end
  local arr=(wrTab==WR_WRITERS and selected.writers) or selected.readers
  tc(C.yellow,(wrTab==WR_WRITERS and "WRITERS  " or "READERS  ")..tostring(arr and #arr or 0))
  ImGui.Separator()
  if not arr or #arr==0 then
    tc(C.dim,"No proven entries in the current index.")
  else
    for i,x in ipairs(arr) do
      tc(wrTab==WR_WRITERS and C.yellow or C.cyan,(wrTab==WR_WRITERS and "WRITE" or "READ").."  ")
      ImGui.SameLine(); ImGui.TextWrapped(safe(x))
      if i<#arr then ImGui.Separator() end
    end
  end
  sep()
  if paddedGlyphButton("wrGraph","VIEW RELATED IN GRAPH",IC.graph,260,34,false) then go(GRAPH,selected) end
  ImGui.SameLine()
  if paddedGlyphButton("wrDetails","OPEN DETAILS",IC.file,190,34,false) then openRecord(selected) end
end

local function graphNodeButton(r,label,idx)
  local text=(label and label.."  " or "")..r.kind..": "..clampText(r.name,28)
  if paddedGlyphButton("graphNode"..idx..r.uid,text,kindIcon(r.kind),ImGui.GetContentRegionAvail(),32,false) then openRecord(r) end
end

local function graphColor(kind)
  if kind=="Quest" then return C.green
  elseif kind=="Fact" then return C.yellow
  elseif kind=="Journal" then return C.cyan
  elseif kind=="Scene" then return C.blue
  elseif kind=="Quest Phase" then return {.66,.55,1,1}
  elseif kind=="Reward" then return {1,.55,.12,1}
  elseif kind=="Item" then return {.78,.86,.92,1}
  elseif kind=="Achievement" then return {1,.82,.18,1}
  end
  return C.dim
end
local function graphU32(c)
  local ok,v=pcall(function() return ImGui.GetColorU32(c[1],c[2],c[3],c[4]) end)
  if ok and v then return v end
  local function b(x) return math.max(0,math.min(255,math.floor((x or 0)*255+.5))) end
  local r,g,bb,a=b(c[1]),b(c[2]),b(c[3]),b(c[4] or 1)
  return r + g*256 + bb*65536 + a*16777216
end
local function graphKindFromText(text)
  local s=lower(text)
  if s:find(".questphase",1,true) then return "Quest Phase" end
  if s:find(".scene",1,true) then return "Scene" end
  if s:find("journal",1,true) then return "Journal" end
  if s:find("reward",1,true) then return "Reward" end
  return "Reference"
end
local function graphTitleFromText(text)
  local s=safe(text)
  local first=s:match("^%s*(.-)%s*::") or s
  first=first:gsub("%.questphase$",""):gsub("%.scene$","")
  return first
end
local function graphTopology(r)
  local nodes={}
  local edges={}
  local seenNodes={}
  local seenEdges={}
  local maxNodes=140
  local maxDepth=12

  local function nodeId(target,title,kind)
    if target and target.uid then return target.uid end
    return "synthetic|"..safe(kind).."|"..safe(title)
  end

  local function addNode(target,title,kind,depth)
    local id=nodeId(target,title,kind)
    if not seenNodes[id] then
      if #nodes>=maxNodes then return nil end
      local n={
        id=id,
        title=title or (target and target.name) or "?",
        kind=kind or (target and target.kind) or "Reference",
        target=target,
        depth=depth or 0
      }
      nodes[#nodes+1]=n
      seenNodes[id]=n
    else
      local n=seenNodes[id]
      if math.abs(depth or 0)<math.abs(n.depth or 0) then n.depth=depth or 0 end
    end
    return seenNodes[id]
  end

  local function addEdge(a,b,label,meta)
    if not a or not b or a.id==b.id then return end
    local k=a.id.."->"..b.id.."|"..safe(label)
    if seenEdges[k] then return end
    seenEdges[k]=true
    edges[#edges+1]={from=a.id,to=b.id,label=label or "related",meta=meta}
  end

  local root=addNode(r,r.name,r.kind,0)

  local function parentRecord(j)
    if not j or not j.parent then return nil end
    return getByUid(j.parent)
  end

  local function sameQuestParent(j,questKey)
    local p=parentRecord(j)
    if not p or p.kind~="Journal" then return false end
    return questTokenFromPath(p.path or "")==questKey
  end

  local function journalChildren(j)
    local out={}
    for _,rel in ipairs(j.related or {}) do
      if lower(rel.label)=="child" then
        local t=getByUid(rel.target)
        if t and t.kind=="Journal" then out[#out+1]=t end
      end
    end
    table.sort(out,function(a,b) return safe(a.name)<safe(b.name) end)
    return out
  end

  local function addJournalTree(parentNode,j,depth)
    if depth>maxDepth or #nodes>=maxNodes then return end
    local n=addNode(j,j.name,j.kind,depth)
    if not n then return end
    addEdge(parentNode,n,"child")
    for _,ch in ipairs(journalChildren(j)) do
      addJournalTree(n,ch,depth+1)
      if #nodes>=maxNodes then break end
    end
  end

  if r.kind=="Quest" then
    -- The old graph flattened every Journal record associated with this quest
    -- into a direct Quest->Journal edge.  Only Journal roots are direct here;
    -- descendants are reached through their actual parent->child links.
    local roots={}
    local extra={}
    local rootSeen={}
    for _,rel in ipairs(r.related or {}) do
      local t=getByUid(rel.target)
      if t then
        if t.kind=="Journal" and lower(rel.label)=="journal" then
          if questTokenFromPath(t.path or "")==r.key and not sameQuestParent(t,r.key) then
            if not rootSeen[t.uid] then roots[#roots+1]=t; rootSeen[t.uid]=true end
          end
        else
          extra[#extra+1]={t=t,label=rel.label}
        end
      end
    end
    table.sort(roots,function(a,b) return safe(a.path)<safe(b.path) end)
    for _,jr in ipairs(roots) do addJournalTree(root,jr,1) end
    for _,x in ipairs(extra) do
      local n=addNode(x.t,x.t.name,x.t.kind,1)
      addEdge(root,n,x.label)
    end

  elseif r.kind=="Journal" then
    -- Walk the true ancestor chain to the left.
    local cur=r
    local curNode=root
    local d=-1
    local guard=0
    while guard<maxDepth do
      guard=guard+1
      local p=parentRecord(cur)
      if not p or p.kind~="Journal" then break end
      local pn=addNode(p,p.name,p.kind,d)
      addEdge(pn,curNode,"child")
      cur=p; curNode=pn; d=d-1
    end

    -- And the real child hierarchy to the right.
    for _,ch in ipairs(journalChildren(r)) do addJournalTree(root,ch,1) end

    -- Show the owning quest once as context, but do not fan every Journal node
    -- back to it.
    for _,rel in ipairs(r.related or {}) do
      if lower(rel.label)=="quest" then
        local q=getByUid(rel.target)
        if q then
          local qn=addNode(q,q.name,q.kind,d)
          addEdge(qn,curNode,"journal")
        end
      end
    end

  else
    -- Facts / seeded phase / scene resources: preserve verified writer/reader
    -- direction, plus direct indexed relationships where the label carries a
    -- direction.  This does not invent node internals that the runtime index
    -- has not actually exposed.
    for _,w in ipairs(r.writers or {}) do
      local n=addNode(nil,graphTitleFromText(w),graphKindFromText(w),-1)
      addEdge(n,root,"sets",w)
    end
    for _,rd in ipairs(r.readers or {}) do
      local n=addNode(nil,graphTitleFromText(rd),graphKindFromText(rd),1)
      addEdge(root,n,"reads",rd)
    end
    for _,rel in ipairs(r.related or {}) do
      local t=getByUid(rel.target)
      if t then
        local l=lower(rel.label)
        if l=="parent" or l=="quest" or l=="writer" or l=="source" or l=="sets" then
          local n=addNode(t,t.name,t.kind,-1)
          addEdge(n,root,rel.label)
        else
          local n=addNode(t,t.name,t.kind,1)
          addEdge(root,n,rel.label)
        end
      end
    end
  end

  return nodes,edges,root.id
end
local function graphExport(r,left,right)
  local path=outputAbs.."WireAtlas_graph_export.txt"
  local ok,err=pcall(function()
    local f=assert(io.open(path,"w"))
    f:write("CP2077 WIRE ATLAS RELATIONSHIP GRAPH\n")
    f:write("Selected: ",safe(r.kind)," | ",safe(r.name)," | ",safe(r.key),"\n\n")
    f:write("WRITERS / SOURCES\n")
    for _,n in ipairs(left) do f:write("  ",safe(n.title)," [",safe(n.kind),"] --",safe(n.label),"--> selected\n") end
    f:write("\nREADERS / RELATED\n")
    for _,n in ipairs(right) do f:write("  selected --",safe(n.label),"--> ",safe(n.title)," [",safe(n.kind),"]\n") end
    f:close()
  end)
  if ok then statusDetail="Graph exported: "..path else statusDetail="Graph export failed: "..safe(err) end
end
local function drawGraphCanvas(r)
  local availW,availH=ImGui.GetContentRegionAvail()
  if not availW or availW<1 then availW=760 end
  if not availH or availH<1 then availH=430 end

  -- Reserve enough height for the existing legend/button row and ImGui item spacing.
  -- The previous 42px budget left the outer graph panel vertically scrollable.
  local controlsH=54
  local paneH=math.max(260,availH-controlsH)
  local white=graphU32({1,1,1,1})
  local socketBlue=graphU32({.24,.66,1,1})
  local wireCol=graphU32({.60,.72,.82,1})
  local wireHot=graphU32({1,.96,.55,1})
  local bg=graphU32({.010,.027,.035,1})
  local grid=graphU32({.045,.115,.135,.9})

  local parents={}
  local children={}
  local seenP,seenC={},{}

  local function pushUnique(arr,seen,target,title,kind,label,meta)
    local id
    if target then
      if target.path and target.path~="" then id=safe(target.kind).."|path|"..safe(target.path)
      else id=target.uid end
    else
      id="synthetic|"..safe(kind).."|"..safe(title).."|"..safe(label)
    end
    if seen[id] then return end
    seen[id]=true
    arr[#arr+1]={
      id=id,target=target,title=title or (target and target.name) or "?",
      kind=kind or (target and target.kind) or "Reference",
      label=label or "related",meta=meta
    }
  end

  local function parentRecord(j)
    if not j or not j.parent then return nil end
    return getByUid(j.parent)
  end

  -- Immediate indexed neighborhood only.
  if r.kind=="Journal" then
    -- Structural Journal-folder parent is NOT automatically a logical graph
    -- predecessor. The logical one-hop predecessor comes from direct graph
    -- edges or from the chain step the user just followed.
    local p=parentRecord(r)

    for _,rel in ipairs(r.related or {}) do
      local t=getByUid(rel.target)
      local l=lower(rel.label)
      if t then
        if l=="child" then
          pushUnique(children,seenC,t,t.name,t.kind,"child")
        elseif l=="quest" then
          -- Quest membership is structural context, not a logical predecessor.
        elseif l=="parent" then
          pushUnique(parents,seenP,t,t.name,t.kind,rel.label)
        elseif l~="child" and l~="quest" then
          -- Other direct relationships stay one hop, direction inferred from label.
          if l=="source" or l=="writer" or l=="sets" then
            pushUnique(parents,seenP,t,t.name,t.kind,rel.label)
          else
            pushUnique(children,seenC,t,t.name,t.kind,rel.label)
          end
        end
      end
    end

  elseif r.kind=="Quest" then
    -- Direct Journal roots only, not the entire descendant tree.
    for _,rel in ipairs(r.related or {}) do
      local t=getByUid(rel.target)
      if t then
        if t.kind=="Journal" and lower(rel.label)=="journal" then
          local tp=parentRecord(t)
          local sameQuestParent=tp and tp.kind=="Journal" and questTokenFromPath(tp.path or "")==r.key
          if questTokenFromPath(t.path or "")==r.key and not sameQuestParent then
            pushUnique(children,seenC,t,t.name,t.kind,"journal")
          end
        else
          local l=lower(rel.label)
          if l=="parent" or l=="source" or l=="writer" or l=="sets" then
            pushUnique(parents,seenP,t,t.name,t.kind,rel.label)
          else
            pushUnique(children,seenC,t,t.name,t.kind,rel.label)
          end
        end
      end
    end

  else
    for _,w in ipairs(r.writers or {}) do
      pushUnique(parents,seenP,nil,graphTitleFromText(w),graphKindFromText(w),"sets",w)
    end
    for _,rd in ipairs(r.readers or {}) do
      pushUnique(children,seenC,nil,graphTitleFromText(rd),graphKindFromText(rd),"reads",rd)
    end
    for _,rel in ipairs(r.related or {}) do
      local t=getByUid(rel.target)
      if t then
        local l=lower(rel.label)
        if l=="parent" or l=="quest" or l=="source" or l=="writer" or l=="sets" then
          pushUnique(parents,seenP,t,t.name,t.kind,rel.label)
        else
          pushUnique(children,seenC,t,t.name,t.kind,rel.label)
        end
      end
    end
  end

  -- Reverse-index only PROVEN immediate incoming edges.
  -- Broad quest/journal membership is deliberately ignored: "belongs to the
  -- same quest" is not the same thing as "is the direct parent of this node".
  for _,candidate in ipairs(records or {}) do
    if candidate.uid~=r.uid then
      for _,rel in ipairs(candidate.related or {}) do
        if rel.target==r.uid then
          local l=lower(rel.label)
          if l=="child" then
            -- candidate -> selected is a real direct parent/child edge.
            pushUnique(parents,seenP,candidate,candidate.name,candidate.kind,"parent")
          elseif l=="sets" or l=="writer" or l=="source" then
            pushUnique(parents,seenP,candidate,candidate.name,candidate.kind,rel.label)
          elseif l=="reads" or l=="reader" then
            pushUnique(children,seenC,candidate,candidate.name,candidate.kind,rel.label)
          end
          -- Ignore quest/journal/related/unknown reverse associations here.
        end
      end
    end
  end

  -- Preserve the exact logical step the user just followed.
  -- If we clicked a child/right-side wire, the previous selected node is the
  -- new node's logical parent. If we clicked a parent/left-side wire, the
  -- previous selected node is the new node's logical child.
  if graphPreviousUid then
    local prev=getByUid(graphPreviousUid)
    if prev and prev.uid~=r.uid then
      if graphPreviousSide=="parent" then
        pushUnique(parents,seenP,prev,prev.name,prev.kind,"previous")
      elseif graphPreviousSide=="child" then
        pushUnique(children,seenC,prev,prev.name,prev.kind,"previous")
      end
    end
  end

  table.sort(parents,function(a,b) return safe(a.title)<safe(b.title) end)
  table.sort(children,function(a,b) return safe(a.title)<safe(b.title) end)

  local function textW(t)
    local ok,w=pcall(function() local x,y=ImGui.CalcTextSize(safe(t)); return x end)
    return (ok and w) or (#safe(t)*8)
  end

  local function detailLines(rec)
    local lines={}
    if rec.recordType then lines[#lines+1]={"Record Type",safe(rec.recordType)} end
    if rec.path then lines[#lines+1]={"Path",safe(rec.path)} end
    if rec.key then lines[#lines+1]={"Identifier",safe(rec.key)} end
    if rec.source then lines[#lines+1]={"Source",safe(rec.source)} end
    if rec.value~=nil then lines[#lines+1]={"Current Value",safe(rec.value)} end
    if rec.state then lines[#lines+1]={"State",safe(rec.state)} end
    lines[#lines+1]={"Writers",tostring(#(rec.writers or {}))}
    lines[#lines+1]={"Readers",tostring(#(rec.readers or {}))}
    return lines
  end

  local centerLines=detailLines(r)
  local centerW=math.max(260,math.min(520,math.max(textW(r.name)+30,340)))
  for _,kv in ipairs(centerLines) do
    centerW=math.max(centerW,math.min(520,textW(kv[1]..": "..kv[2])+34))
  end
  local centerH=74+#centerLines*19+32

  local neighborW=210
  local neighborH=94
  local sideGap=86
  local verticalGap=22
  local marginX=34
  local marginY=34

  local maxSideCount=math.max(#parents,#children,1)
  local sideStackH=maxSideCount*neighborH+(maxSideCount-1)*verticalGap
  local contentH=math.max(centerH,sideStackH)
  local canvasH=math.max(paneH-8,marginY*2+contentH)

  local hasLeft=(#parents>0)
  local hasRight=(#children>0)
  local contentW=centerW + (hasLeft and (neighborW+sideGap) or 0) + (hasRight and (neighborW+sideGap) or 0)
  local groupStart
  if contentW<=availW-20 then groupStart=math.max(10,(availW-contentW)*.5)
  else groupStart=marginX end

  local leftX=groupStart
  local centerX=groupStart + (hasLeft and (neighborW+sideGap) or 0)
  local rightX=centerX+centerW+(hasRight and sideGap or 0)
  local centerY=marginY+math.max(0,(contentH-centerH)*.5)
  local virtualW=math.max(availW-8,groupStart+contentW+marginX)

  local function stackY(i,count)
    if count<=0 then return centerY end
    local total=count*neighborH+(count-1)*verticalGap
    local start=marginY+math.max(0,(contentH-total)*.5)
    return start+(i-1)*(neighborH+verticalGap)
  end

  local HORIZONTAL_SCROLLBAR=2048
  local NO_SCROLLBAR=8
  local NO_SCROLL_WITH_MOUSE=16
  local needH=(contentW+20)>availW
  local needV=(contentH+marginY*2)>paneH
  local canvasFlags=0
  if needH then canvasFlags=HORIZONTAL_SCROLLBAR end
  if not needH and not needV then canvasFlags=NO_SCROLLBAR+NO_SCROLL_WITH_MOUSE end

  local childContentW=needH and virtualW or math.max(1,availW-6)
  local childContentH=needV and canvasH or math.max(1,paneH-6)
  ImGui.SetNextWindowContentSize(childContentW,childContentH)
  ImGui.BeginChild("##wireAtlasGraphCanvas",availW,paneH,true,canvasFlags)

  if graphResetRequested then
    ImGui.SetScrollX(0); ImGui.SetScrollY(0); graphResetRequested=false
  end
  if graphFitRequested then
    if needH then ImGui.SetScrollFromPosX(centerX+centerW*.5,.5) else ImGui.SetScrollX(0) end
    if needV then ImGui.SetScrollFromPosY(centerY+centerH*.5,.5) else ImGui.SetScrollY(0) end
    graphFitRequested=false
  end

  local sx,sy=ImGui.GetCursorScreenPos()
  local draw=ImGui.GetWindowDrawList()
  ImGui.ImDrawListAddRectFilled(draw,sx,sy,sx+virtualW,sy+canvasH,bg,0)
  for gx=sx,sx+virtualW,24 do ImGui.ImDrawListAddLine(draw,gx,sy,gx,sy+canvasH,grid,1) end
  for gy=sy,sy+canvasH,24 do ImGui.ImDrawListAddLine(draw,sx,gy,sx+virtualW,gy,grid,1) end

  local mouseX,mouseY=ImGui.GetMousePos()
  local hoveredWire=nil
  local hoveredDist=99999

  local function segDist(px,py,x1,y1,x2,y2)
    local vx,vy=x2-x1,y2-y1
    local wx,wy=px-x1,py-y1
    local vv=vx*vx+vy*vy
    if vv<.001 then
      local dx,dy=px-x1,py-y1
      return math.sqrt(dx*dx+dy*dy)
    end
    local t=(wx*vx+wy*vy)/vv
    if t<0 then t=0 elseif t>1 then t=1 end
    local qx,qy=x1+t*vx,y1+t*vy
    local dx,dy=px-qx,py-qy
    return math.sqrt(dx*dx+dy*dy)
  end

  local wires={}
  local function makeWire(side,item,index,count)
    local y=stackY(index,count)+neighborH*.5
    local cy=centerY+centerH*.5
    local spread=(count<=1) and cy or (centerY+34+((index-1)/(count-1))*math.max(1,centerH-68))
    local p
    if side=="left" then
      p={
        {x=sx+leftX+neighborW,y=sy+y},
        {x=sx+leftX+neighborW+36,y=sy+y},
        {x=sx+centerX-36,y=sy+spread},
        {x=sx+centerX,y=sy+spread}
      }
    else
      p={
        {x=sx+centerX+centerW,y=sy+spread},
        {x=sx+centerX+centerW+36,y=sy+spread},
        {x=sx+rightX-36,y=sy+y},
        {x=sx+rightX,y=sy+y}
      }
    end
    wires[#wires+1]={side=side,item=item,p=p,index=index}
  end
  for i,item in ipairs(parents) do makeWire("left",item,i,#parents) end
  for i,item in ipairs(children) do makeWire("right",item,i,#children) end

  for wi,w in ipairs(wires) do
    for i=1,#w.p-1 do
      local a,b=w.p[i],w.p[i+1]
      local d=segDist(mouseX,mouseY,a.x,a.y,b.x,b.y)
      if d<=8 and d<hoveredDist then hoveredDist=d; hoveredWire=wi end
    end
  end

  local function drawArrow(a,b,col,th)
    local dx,dy=b.x-a.x,b.y-a.y
    local len=math.sqrt(dx*dx+dy*dy); if len<1 then len=1 end
    local ux,uy=dx/len,dy/len
    local px,py=-uy,ux
    local ax=b.x-ux*8; local ay=b.y-uy*8
    ImGui.ImDrawListAddLine(draw,b.x,b.y,ax+px*4,ay+py*4,col,th)
    ImGui.ImDrawListAddLine(draw,b.x,b.y,ax-px*4,ay-py*4,col,th)
  end

  local followedKey=graphFollowEdgeKey
  for wi,w in ipairs(wires) do
    local key=(w.item.id or "").."|"..w.side.."|"..safe(w.item.label)
    local hot=(hoveredWire==wi) or (graphFollowFrames>0 and followedKey==key)
    local col=hot and wireHot or wireCol
    local th=hot and 3 or 1.7
    for i=1,#w.p-1 do
      ImGui.ImDrawListAddLine(draw,w.p[i].x,w.p[i].y,w.p[i+1].x,w.p[i+1].y,col,th)
    end
    local q,z=w.p[#w.p-1],w.p[#w.p]
    drawArrow(q,z,col,th)

    local label=safe(w.item.label)
    if label~="" then
      local tw,thh=ImGui.CalcTextSize(label)
      local p2,p3=w.p[2],w.p[3]
      if math.abs(p3.x-p2.x)>tw+18 then
        ImGui.ImDrawListAddText(draw,(p2.x+p3.x-tw)*.5,(p2.y+p3.y)*.5-16,col,label)
      end
    end
  end

  local function fitNodeText(text,maxWidth)
    text=safe(text)
    local tw,th=ImGui.CalcTextSize(text)
    if tw<=maxWidth then return text end
    local ell="..."
    local ellW=ImGui.CalcTextSize(ell)
    local lo,hi=0,#text
    while lo<hi do
      local mid=math.floor((lo+hi+1)/2)
      local probe=text:sub(1,mid)..ell
      local pw,ph=ImGui.CalcTextSize(probe)
      if pw<=maxWidth then lo=mid else hi=mid-1 end
    end
    return text:sub(1,lo)..ell
  end

  local function headerBodyNode(x,y,w,h,kind,title,details,isSelected,id,target,relation)
    local cat=graphColor(kind)
    local headerCol=graphU32({cat[1],cat[2],cat[3],1})
    local bodyCol=graphU32({.035,.045,.055,1})
    local borderCol=isSelected and graphU32({1,.86,.25,1}) or graphU32({.32,.42,.50,1})
    local headerH=28

    ImGui.ImDrawListAddRectFilled(draw,x,y,x+w,y+h,bodyCol,4)
    ImGui.ImDrawListAddRectFilled(draw,x,y,x+w,y+headerH,headerCol,4)
    ImGui.ImDrawListAddRect(draw,x,y,x+w,y+h,borderCol,4,0,isSelected and 3 or 1.5)

    ImGui.ImDrawListAddText(draw,x+9,y+7,white,safe(title))
    ImGui.ImDrawListAddText(draw,x+9,y+headerH+7,graphU32({.78,.86,.92,1}),safe(kind))

    local yy=y+headerH+26
    for _,kv in ipairs(details or {}) do
      local line=safe(kv[1])..": "..safe(kv[2])
      if yy+16<y+h-8 then
        ImGui.ImDrawListAddText(draw,x+9,yy,white,fitNodeText(line,w-18))
        yy=yy+19
      end
    end

    ImGui.SetCursorScreenPos(x,y)
    ImGui.InvisibleButton("##wkNode"..id,w,h)
    if target and ImGui.IsItemClicked() then
      local oldSelected=selected
      graphPreviousUid=oldSelected and oldSelected.uid or nil
      -- A left-side neighbor becomes center: the old center is its logical child.
      -- A right-side neighbor becomes center: the old center is its logical parent.
      if id:sub(1,1)=="P" then graphPreviousSide="child"
      elseif id:sub(1,1)=="C" then graphPreviousSide="parent"
      else graphPreviousSide=nil end

      selected=target
      selectedHistory[#selectedHistory+1]=target.uid
      graphResetRequested=false
      graphFitRequested=true
      graphFollowFrames=0
      graphFollowEdgeKey=nil
      statusDetail="Graph recentered on "..safe(target.name)
    end
  end

  local function neighborDetails(item)
    local d={}
    if item.target then
      if item.target.state then d[#d+1]={"State",item.target.state} end
      if item.target.path then d[#d+1]={"Path",clampText(item.target.path,26)} end
      if item.target.value~=nil then d[#d+1]={"Value",item.target.value} end
    end
    d[#d+1]={"Link",item.label}
    return d
  end

  for i,item in ipairs(parents) do
    local y=stackY(i,#parents)
    headerBodyNode(sx+leftX,sy+y,neighborW,neighborH,item.kind,item.title,neighborDetails(item),false,"P"..i,item.target,item.label)
  end

  for i,item in ipairs(children) do
    local y=stackY(i,#children)
    headerBodyNode(sx+rightX,sy+y,neighborW,neighborH,item.kind,item.title,neighborDetails(item),false,"C"..i,item.target,item.label)
  end

  headerBodyNode(sx+centerX,sy+centerY,centerW,centerH,r.kind,r.name,centerLines,true,"CENTER",nil,nil)

  -- WolvenKit-style sockets: one real visible socket per one-hop relationship.
  for wi,w in ipairs(wires) do
    local hot=(hoveredWire==wi)
    local col=hot and wireHot or socketBlue
    local first,last=w.p[1],w.p[#w.p]
    ImGui.ImDrawListAddCircleFilled(draw,first.x,first.y,4.5,col,16)
    ImGui.ImDrawListAddCircleFilled(draw,last.x,last.y,4.5,col,16)
  end

  if hoveredWire then
    local w=wires[hoveredWire]
    ImGui.BeginTooltip()
    if w.side=="left" then
      ImGui.Text("FROM"); ImGui.Separator()
      ImGui.Text(w.item.title); ImGui.Text("("..safe(w.item.kind)..")")
      ImGui.Spacing(); ImGui.Text("RELATION"); ImGui.Separator(); ImGui.Text(safe(w.item.label))
      if w.item.meta and w.item.meta~="" then ImGui.TextWrapped(safe(w.item.meta)) end
      ImGui.Spacing(); ImGui.Text("TO"); ImGui.Separator()
      ImGui.Text(r.name); ImGui.Text("("..safe(r.kind)..")")
    else
      ImGui.Text("FROM"); ImGui.Separator()
      ImGui.Text(r.name); ImGui.Text("("..safe(r.kind)..")")
      ImGui.Spacing(); ImGui.Text("RELATION"); ImGui.Separator(); ImGui.Text(safe(w.item.label))
      if w.item.meta and w.item.meta~="" then ImGui.TextWrapped(safe(w.item.meta)) end
      ImGui.Spacing(); ImGui.Text("TO"); ImGui.Separator()
      ImGui.Text(w.item.title); ImGui.Text("("..safe(w.item.kind)..")")
    end
    if w.item.target then
      ImGui.Spacing()
      tc(C.dim,"Click wire to follow this relationship one step.")
    end
    ImGui.EndTooltip()

    local mouseDown=false
    local okDown,valDown=pcall(function() return ImGui.IsMouseDown(0) end)
    if okDown and valDown then mouseDown=true end
    local clicked=mouseDown and not graphWireMouseLatch
    if mouseDown then graphWireMouseLatch=true end

    if clicked then
      if w.item.target then
        local oldSelected=selected
        graphPreviousUid=oldSelected and oldSelected.uid or nil
        graphPreviousSide=(w.side=="right") and "parent" or "child"

        selected=w.item.target
        selectedHistory[#selectedHistory+1]=w.item.target.uid
        graphResetRequested=false
        graphFitRequested=true
        graphFollowEdgeKey=(w.item.id or "").."|"..w.side.."|"..safe(w.item.label)
        graphFollowFrames=60
        statusDetail="Followed "..safe(w.item.label).." to "..safe(w.item.target.name)
      else
        statusDetail="This wire has no indexed destination record to follow."
      end
    end
  end

  local latchDown=false
  local okLatch,valLatch=pcall(function() return ImGui.IsMouseDown(0) end)
  if okLatch and valLatch then latchDown=true end
  if not latchDown then graphWireMouseLatch=false end

  ImGui.SetCursorScreenPos(sx,sy)
  ImGui.Dummy(virtualW,canvasH)
  ImGui.EndChild()

  -- Static legend: intentionally outside the scrollable graph child.
  ImGui.Spacing()
  local legendX,legendY=ImGui.GetCursorScreenPos()
  local legendDraw=ImGui.GetWindowDrawList()
  local lx=legendX
  local ly=legendY
  local legend={{"Quest",C.green},{"Fact",C.yellow},{"Journal",C.cyan},{"Scene",C.blue},{"Quest Phase",{.66,.55,1,1}}}
  for _,e in ipairs(legend) do
    ImGui.ImDrawListAddRectFilled(legendDraw,lx,ly+3,lx+11,ly+14,graphU32(e[2]),2)
    ImGui.ImDrawListAddText(legendDraw,lx+16,ly,white,e[1])
    lx=lx+({Quest=68,Fact=58,Journal=78,Scene=67,["Quest Phase"]=104})[e[1]]
  end
  -- Keep the legend left-aligned and the viewport controls on its right.
  -- Both share a single row outside the scrollable graph canvas.
  local buttonsW=118+132+8
  local buttonsX=legendX+math.max(lx-legendX+12,availW-buttonsW)
  ImGui.SetCursorScreenPos(buttonsX,legendY)
  if paddedGlyphButton("graphReset","RESET",IC.refresh,118,32,false) then
    graphResetRequested=true
    graphPreviousUid=nil
    graphPreviousSide=nil
    graphFollowFrames=0
    graphFollowEdgeKey=nil
    statusDetail="Graph viewport reset."
  end
  ImGui.SameLine()
  if paddedGlyphButton("graphFit","FIT VIEW",IC.browse,132,32,false) then
    graphFitRequested=true
    statusDetail="Graph centered on the selected node."
  end
end
local function graphInformationPage()
  -- Approved eight-section one-hop logic inspector reference.
  local function heading(s)
    ImGui.Spacing(); tc(C.yellow,s); ImGui.Separator(); ImGui.Spacing()
  end
  local function subheading(s)
    ImGui.Spacing(); tc(C.cyan,s); ImGui.Spacing()
  end
  local function paragraph(s)
    ImGui.TextWrapped(s); ImGui.Spacing()
  end
  tc(C.yellow,"WIRE ATLAS - GRAPH INFORMATION")
  tc(C.dim,"ONE-HOP LOGIC INSPECTOR  |  TECHNICAL REFERENCE")
  ImGui.Spacing()
  heading("1. PURPOSE OF THE ONE-HOP LOGIC INSPECTOR")
  paragraph("The Wire Atlas Relationship Graph is a one-hop logic inspector designed to examine the immediate connections surrounding a selected Cyberpunk 2077 game record.")
  paragraph("Its purpose is to help researchers investigate how quests, facts, journal entries, scenes, quest phases, and other indexed records relate to one another without overwhelming the display with an entire network of connections.")
  paragraph("Instead of attempting to reconstruct a complete quest execution graph, Wire Atlas presents the selected record and its directly available incoming and outgoing relationships.")
  paragraph("Each connection can be examined individually, allowing researchers to follow known relationships through the index while retaining the context of the record currently being investigated.")
  paragraph("The graph combines information from runtime game systems with previously researched references. It distinguishes documented operations from structural and identifier-based associations rather than treating every connection as proof of a direct execution dependency.")
  heading("2. HOW ONE-HOP INSPECTION WORKS")
  paragraph("A hop is a connection between the selected record and another record represented in the current index.")
  paragraph("The graph organizes these connections into three areas.")
  subheading("INCOMING - LEFT")
  paragraph("Contains known incoming relationships, including documented writers, source references, direct parent relationships, and other connections classified as incoming.")
  subheading("SELECTED RECORD - CENTER")
  paragraph("Represents the current research focus. Its details can include the record identifier, type, source, path, current fact value, journal state, and known writer/reader counts.")
  subheading("OUTGOING - RIGHT")
  paragraph("Contains known outgoing relationships, including documented readers, direct child relationships, and other indexed connections.")
  paragraph("Selecting a connected record makes it the new center of the graph. Wire Atlas then rebuilds the display around that record's immediate relationships.")
  paragraph("This approach allows researchers to investigate complex systems progressively without displaying every connected record at once.")
  paragraph("One-hop describes the visible relationship depth, not the maximum distance an investigation can travel. A researcher can continue following available connections from one record to another.")
  subheading("JOURNAL AND QUEST RELATIONSHIPS")
  paragraph("Journal records expose hierarchical information through parent and child relationships.")
  paragraph("Wire Atlas uses direct indexed connections and preserves relevant navigation context when moving between journal entries.")
  paragraph("For Quest records, the graph displays associated journal roots rather than expanding every descendant into the same view.")
  paragraph("Journal hierarchy provides useful structural information, but it does not automatically establish the order in which quest logic executes.")
  heading("3. NODES AND RECORD INFORMATION")
  paragraph("Nodes represent indexed game records or known source references.")
  paragraph("The selected record appears in the center with more detailed information than its neighboring nodes.")
  subheading("CENTRAL RECORD")
  paragraph("Depending on the record type and available information, the central node can display:")
  ImGui.BulletText("Record name, type, and internal identifier")
  ImGui.BulletText("TweakDB record type or journal path")
  ImGui.BulletText("Source information")
  ImGui.BulletText("Current fact value or journal state")
  ImGui.BulletText("Known writer and reader counts")
  paragraph("These fields help establish what the record represents, where its information originated, and which known relationships may warrant further investigation.")
  paragraph("Writer and reader counts represent references stored in the current index. They are not guaranteed totals for every operation performed by the game.")
  subheading("CONNECTED RECORDS")
  paragraph("Neighboring nodes identify related records and show available information such as their state, path, value, and relationship label.")
  paragraph("Some long identifiers or paths are abbreviated to fit the node. This is a display adjustment, not a modification of the underlying record.")
  subheading("RECORD COLORS")
  paragraph("Quest - Green; Fact - Yellow; Journal - Cyan; Scene - Blue; Quest Phase - Purple; Reward - Orange; Item - Light gray; Achievement - Gold.")
  paragraph("These colors identify record categories. They do not indicate whether a quest is completed, a fact is active, or an item is owned.")
  paragraph("Source references that do not match a recognized record category use the graph's default reference styling.")
  paragraph("The inline legend beneath the graph identifies its primary record categories.")
  heading("4. WIRES AND RELATIONSHIP DIRECTION")
  paragraph("Wires connect records through visible sockets and represent relationships stored in the current index.")
  paragraph("Their direction follows the relationship classification used by Wire Atlas.")
  paragraph("SETS - A documented source associated with writing or modifying a record.")
  paragraph("READS - A documented source associated with checking or referencing a record.")
  paragraph("PARENT / CHILD - A structural relationship between records, particularly journal entries.")
  paragraph("QUEST / JOURNAL - An association between a quest and its journal structure.")
  paragraph("SOURCE / WRITER - An indexed association identifying a source or writer relationship.")
  paragraph("RELATED - An association whose significance depends on the underlying indexed information.")
  paragraph("Other labels may appear when provided by the index.")
  subheading("UNDERSTANDING WIRE DIRECTION")
  paragraph("A wire's direction describes how Wire Atlas represents the relationship. It does not necessarily describe the order in which game operations execute.")
  paragraph("For example, a writer connection may identify a source known to modify a fact. A journal parent-child connection, however, describes hierarchy rather than proving that one objective must execute before another.")
  paragraph("Likewise, records sharing a quest identifier may be associated without having a direct execution dependency.")
  subheading("WIRE INSPECTION")
  paragraph("Hovering over a wire displays the available relationship information, including its source, destination, and relationship label.")
  paragraph("Where supported, the tooltip also displays the research annotation associated with the connection.")
  paragraph("These annotations can identify known resources or operations and provide context beyond the visible relationship label.")
  heading("5. FOLLOWING RELATIONSHIPS")
  paragraph("Wire Atlas supports progressive navigation through indexed connections.")
  paragraph("Selecting a neighboring record changes the current research focus and rebuilds the one-hop graph around the newly selected record.")
  paragraph("Selecting a wire with an indexed destination can follow that relationship directly.")
  paragraph("The graph also preserves the immediate navigation context of the relationship just followed, allowing the previous record to remain represented as a connected neighbor when appropriate.")
  paragraph("This is useful when investigating a chain of relationships because it helps maintain continuity between successive views.")
  subheading("RESEARCHED SOURCE REFERENCES")
  paragraph("Some writer and reader connections originate from previously researched resource information rather than complete records discovered through runtime indexing.")
  paragraph("These references may identify scenes, quest phases, or known operations. They can appear in the graph even when Wire Atlas does not have a complete record available to inspect.")
  paragraph("In those cases, the connection remains visible as supporting information, but it cannot be followed into a record that Wire Atlas does not possess.")
  paragraph("Wire Atlas does not invent missing records, resource nodes, or connections to complete a relationship chain.")
  heading("6. GRAPH CONTROLS AND NAVIGATION")
  paragraph("The graph uses a scrollable canvas to accommodate records with more connections than can fit within the available display area.")
  paragraph("Its controls are positioned beneath the canvas alongside the inline legend.")
  subheading("RESET")
  paragraph("Restores the graph screen to its default viewing position.")
  subheading("FIT VIEW")
  paragraph("Centers the selected record within the available viewport when scrolling is necessary.")
  paragraph("It preserves the existing node dimensions rather than reducing the entire graph to fit every connection on the screen.")
  subheading("GRAPH SCROLLING")
  paragraph("The graph provides horizontal or vertical scrolling when its contents exceed the available canvas.")
  paragraph("The surrounding interface remains separate from the graph's internal scrolling area.")
  subheading("INLINE LEGEND")
  paragraph("The legend provides a persistent visual reference for the primary record colors.")
  paragraph("It remains beneath the graph alongside RESET and FIT VIEW, eliminating the need for a separate Legend screen.")
  heading("7. UNDERSTANDING THE EVIDENCE")
  paragraph("The Relationship Graph brings together different kinds of information, but not every connection establishes the same thing.")
  paragraph("Understanding those differences is essential when investigating game logic.")
  subheading("DOCUMENTED WRITERS")
  paragraph("A writer identifies a known source associated with modifying a record.")
  paragraph("Where available, research annotations may identify a scene, quest-phase resource, node reference, or recorded operation.")
  paragraph("This information can help researchers identify where a game-state change originates.")
  subheading("DOCUMENTED READERS")
  paragraph("A reader identifies a known source associated with checking or referencing a record.")
  paragraph("Reader information can help identify resources that depend on a particular fact or other indexed value.")
  subheading("STRUCTURAL RELATIONSHIPS")
  paragraph("Journal parent-child relationships describe how entries are organized within the game's journal system.")
  paragraph("These relationships can help establish context and hierarchy, but they do not independently reveal the conditions required for progression.")
  subheading("IDENTIFIER-BASED ASSOCIATIONS")
  paragraph("Some connections are established through matching identifiers or shared quest references.")
  paragraph("These associations are useful for locating related information, but they do not automatically establish a writer, reader, or execution dependency.")
  subheading("INTERPRETING MISSING CONNECTIONS")
  paragraph("An empty side of the graph does not prove that a record has no incoming or outgoing relationships in Cyberpunk 2077.")
  paragraph("It means Wire Atlas has no qualifying connections available to display for that side of the current one-hop view.")
  paragraph("Similarly, a missing writer or reader does not establish that the corresponding operation does not exist.")
  paragraph("The graph represents the evidence available in its index, not every possible relationship in the game's resources.")
  heading("8. DATA COVERAGE AND LIMITATIONS")
  paragraph("The One-Hop Logic Inspector uses the records and relationships available through Wire Atlas's current runtime index and researched reference data.")
  paragraph("Its coverage depends on the information exposed by the game's supported systems and the verified references included with the application.")
  paragraph("The graph can identify indexed relationships, display known source information, expose available record values and states, and support investigation through connected records.")
  paragraph("It does not automatically reconstruct every quest-phase node, scene operation, condition, branch, or execution path.")
  subheading("RUNTIME INFORMATION")
  paragraph("Current fact values and journal states depend on the information available from the game session and the latest refresh performed by Wire Atlas.")
  paragraph("The graph should not be interpreted as a continuous historical record of changes or as a live execution tracer.")
  subheading("RESEARCH BOUNDARIES")
  paragraph("A connection is evidence of an indexed association. Its specific meaning depends on its label, source, and supporting information.")
  subheading("READ-ONLY OPERATION")
  paragraph("The graph is an inspection interface.")
  paragraph("Following connections, selecting records, inspecting wires, and adjusting the viewport do not intentionally modify quest facts, journal states, inventory, achievements, or saved-game data.")
end
local function graphPage()
  if not selected then tc(C.dim,"No record selected."); return end
  breadcrumb({selected.kind,selected.name,"Graph"})
  subTabs({"GRAPH","INFORMATION"},graphTab,function(v) graphTab=v end)

  if graphTab==GRAPH_MAIN then
    local ok,err=pcall(function() drawGraphCanvas(selected) end)
    if not ok then
      tc(C.red or {1,.25,.25,1},"GRAPH RENDER ERROR")
      ImGui.Separator()
      ImGui.TextWrapped(safe(err))
      ImGui.Separator()
      tc(C.dim,"The relationship index is intact; this message is only the canvas renderer failure.")
    end
  elseif graphTab==GRAPH_INFORMATION then
    graphInformationPage()
  end
end

local function journalPage()
  if not selected or selected.kind~="Journal" then tc(C.dim,"Select a Journal record first."); return end
  breadcrumb({"Browse","Journal",selected.name})
  subTabs({"TREE","ENTRY","RELATED"},journalTab,function(v) journalTab=v end)

  if journalTab==JOURNAL_TREE then
    ImGui.BeginChild("JournalTree",360,0,true)
    tc(C.yellow,"JOURNAL TREE")
    local treeW=ImGui.GetContentRegionAvail()
    if selected.parent then
      local p=getByUid(selected.parent)
      if p and relatedRecordButton("jparent"..p.uid,p,"parent",treeW,30) then openRecord(p) end
      ImGui.Spacing()
    end
    local n=0
    for _,rel in ipairs(selected.related or {}) do
      if rel.label=="child" then
        local ch=getByUid(rel.target)
        if ch then
          n=n+1
          if relatedRecordButton("jchild"..n..ch.uid,ch,"child",treeW,30) then openRecord(ch) end
          ImGui.Spacing()
        end
      end
    end
    if n==0 then tc(C.dim,"No indexed children.") end
    ImGui.EndChild()
    ImGui.SameLine()
    ImGui.BeginChild("JournalTreeDetail",0,0,true)
    tc(C.yellow,selected.name); tc(C.cyan,"Journal Entry"); sep()
    tc(stateColor(selected.state),selected.state or "Unknown")
    ImGui.TextWrapped(selected.path or selected.key)
    ImGui.Text("Hash: "..safe(selected.hash))
    ImGui.EndChild()
  elseif journalTab==JOURNAL_ENTRY then
    tc(C.yellow,selected.name); tc(C.cyan,"Journal Entry")
    sep()
    ImGui.TextWrapped("Path: "..safe(selected.path or selected.key))
    tc(stateColor(selected.state),"Status: "..safe(selected.state))
    ImGui.Text("ID: "..safe(selected.id))
    ImGui.Text("Hash: "..safe(selected.hash))
    ImGui.Text("Writers: "..#(selected.writers or {}))
    if paddedGlyphButton("journalWriters","VIEW WRITERS / READERS",IC.link,260,34,false) then go(WRITERS,selected) end
    ImGui.SameLine()
    if paddedGlyphButton("journalGraph","VIEW GRAPH",IC.graph,170,34,false) then go(GRAPH,selected) end
  else
    drawRelated(selected)
  end
end

local function inspectCommonRecord(r)
  ImGui.Text("Identifier: "..safe(r.key)); ImGui.Text("Source:     "..safe(r.source)); if r.recordType then ImGui.Text("Record Type: "..r.recordType) end
  if r.record then
    local tags=tryMethod(r.record,"Tags") or tryMethod(r.record,"tags")
    if type(tags)=="table" and #tags>0 then tc(C.yellow,"Tags"); for _,t in ipairs(tags) do ImGui.BulletText(safe(t)) end end
  end
end
local function itemPage()
  if not selected or (selected.kind~="Item" and selected.kind~="Reward") then tc(C.dim,"Select an Item or Reward record first."); return end
  breadcrumb({"Browse",selected.kind.."s",selected.name})
  subTabs({"OVERVIEW","CONDITIONS","RELATED"},itemTab,function(v) itemTab=v end)

  tc(C.yellow,kindIcon(selected.kind).."  "..selected.name)
  tc(C.cyan,selected.kind)
  sep()

  if itemTab==ITEM_OVERVIEW then
    ImGui.Columns(2,"ItemCols",true)
    ImGui.Text("Identifier"); ImGui.NextColumn(); tc(C.cyan,safe(selected.key)); ImGui.NextColumn()
    ImGui.Text("Source"); ImGui.NextColumn(); ImGui.Text(safe(selected.source)); ImGui.NextColumn()
    if selected.recordType then ImGui.Text("Record Type"); ImGui.NextColumn(); ImGui.TextWrapped(selected.recordType); ImGui.NextColumn() end
    ImGui.Columns(1)
    sep()
    tc(C.yellow,"RELATED")
    local rels=relatedRecords(selected,10)
    local cap=ImGui.GetContentRegionAvail()
    for i,x in ipairs(rels) do
      if relatedRecordButton("item"..i..x.r.uid,x.r,x.label,cap,30) then openRecord(x.r) end
      ImGui.Spacing()
    end
    if #rels==0 then tc(C.dim,"No indexed relationships.") end
  elseif itemTab==ITEM_CONDITIONS then
    tc(C.dim,"Conditions are displayed only when the index has a proven relationship. Nothing is inferred from record names alone.")
    if #(selected.writers or {})>0 then sep(); tc(C.yellow,"KNOWN SOURCES"); for _,x in ipairs(selected.writers) do ImGui.TextWrapped(x) end end
  else
    drawRelated(selected)
  end
end

local function footer()
  tc(C.dim,"READ ONLY")
  ImGui.SameLine()
  tc(C.dim," | ")
  ImGui.SameLine()
  tc(C.dim,indexBuilt and ("INDEXED "..#records.." RECORDS") or "INDEX NOT BUILT")
end

registerForEvent("onInit",function()
  statusText="READY"; statusDetail="Building static game index; live save state will attach after player detection."; probeBridge()
  autoBuildPending=false; autoBuildAttempted=true; buildQueued=true
  liveSessionAttached=false; wasPlayable=false
end)
registerForEvent("onUpdate",function(delta)
  if buildQueued and not indexing then rebuildIndex() end

  local playable=isPlayableSession()
  if playable and not wasPlayable then
    if indexBuilt then refreshLiveState() end
  elseif not playable and wasPlayable then
    liveSessionAttached=false
    liveStats={facts=0,journal=0,active=0,succeeded=0,failed=0}
    if indexBuilt then
      statusText="READY"
      statusDetail="Static index ready. Waiting for a playable save to attach live state."
    end
  end
  wasPlayable=playable
end)
registerForEvent("onOverlayOpen",function() overlay=true; probeBridge() end)
registerForEvent("onOverlayClose",function() overlay=false end)
registerForEvent("onDraw",function()
  if not overlay then return end
  pushTheme()
  if resizeMode=="collapsed" then ImGui.SetNextWindowSize(430,54,ImGuiCond.Always)
  elseif resizeMode=="expanded" then ImGui.SetNextWindowSize(1120,800,ImGuiCond.Always) end
  local visible=ImGui.Begin(NAME.."##WireAtlas",true,ImGuiWindowFlags.NoTitleBar+ImGuiWindowFlags.NoCollapse+ImGuiWindowFlags.NoScrollbar)
  resizeMode=nil
  if visible then
    header()
    if not collapsed then
      mainNav()
      if page==HOME then
        ImGui.BeginChild("WireAtlasMain",0,-30,true,ImGuiWindowFlags.NoScrollbar)
      else
        ImGui.BeginChild("WireAtlasMain",0,-30,true)
      end
      if page==HOME then homePage()
      elseif page==HELP then helpPage()
      elseif page==BROWSE then browsePage()
      elseif page==LIST then listPage()
      elseif page==SEARCH then searchPage()
      elseif page==DETAIL then detailPage()
      elseif page==WRITERS then writersPage()
      elseif page==GRAPH then graphPage()
      elseif page==JOURNAL then journalPage()
      elseif page==ITEM then itemPage() end
      ImGui.EndChild(); footer()
    end
  end
  ImGui.End(); popTheme()
end)

print("["..NAME.."] "..VER.." loaded")
