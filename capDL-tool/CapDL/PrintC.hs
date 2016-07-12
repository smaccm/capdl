--
-- Copyright 2014, NICTA
--
-- This software may be distributed and modified according to the terms of
-- the BSD 2-Clause license. Note that NO WARRANTY is provided.
-- See "LICENSE_BSD2.txt" for details.
--
-- @TAG(NICTA_BSD)
--

-- Printer for C source format to be consumed by the CapDL initialiser.
-- Note: corresponds to the -c/--code argument.

{-# LANGUAGE CPP #-}

module CapDL.PrintC where

import CapDL.Model

import Control.Exception (assert)
import Data.List.Compat
import Data.List.Utils
import Data.Maybe (isJust, fromJust, fromMaybe)
import Prelude ()
import Prelude.Compat
import Data.Map as Map
import Data.Set as Set
import Data.Bits
import Numeric (showHex)
import Text.PrettyPrint

(∈) = Set.member

(+++) :: String -> String -> String
s1 +++ s2 = s1 ++ "\n" ++ s2

hex :: Word -> String
hex x = "0x" ++ showHex x ""

maxObjects :: Int -> String
maxObjects count = "#define MAX_OBJECTS " ++ show count

memberArch :: Arch -> String
memberArch arch =
    "#if !defined(CONFIG_ARCH_" ++ a ++ ")" +++
    "#    error \"invalid target architecture; expecting " ++ a ++ "\"" +++
    "#endif"
    where
        a = case arch of
            IA32 -> "IA32"
            ARM11 -> "ARM"
            X86_64 -> "X86_64"

memberNum :: Int -> String
memberNum n = ".num = " ++ show n ++ ","

showObjID :: Map ObjID Int -> ObjID -> String
showObjID xs id = (case Map.lookup id xs of
    Just w -> show w
    _ -> "INVALID_SLOT") ++ " /* " ++ fst id ++ " */"

showRights :: CapRights -> String
showRights rights =
    "(" ++ intercalate "|" (["0"] ++ r ++ w ++ g) ++ ")"
    where
        r = if Read ∈ rights then  ["seL4_CanRead"]  else []
        w = if Write ∈ rights then ["seL4_CanWrite"] else []
        g = if Grant ∈ rights then ["seL4_CanGrant"] else []

showPorts :: Set Word -> String
showPorts ports =
    show ((.|.) (shift start 16) end)
    where
        start = Set.findMin ports
        end = Set.findMax ports

showPCI :: Word -> (Word, Word, Word) -> String
showPCI domainID (pciBus, pciDev, pciFun) =
    hex $ shift domainID 16 .|. shift pciBus 8 .|. shift pciDev 3 .|. pciFun

-- Lookup-by-value on a dictionary. I feel like I need a shower.
lookupByValue :: Ord k => (a -> Bool) -> Map k a -> k
lookupByValue f m = head $ keys $ Map.filter f m

showCap :: Map ObjID Int -> Cap -> IRQMap -> String -> ObjMap Word -> String
showCap _ NullCap _ _ _ = "{.type = CDL_NullCap}"
showCap objs (UntypedCap id) _ _ _ =
    "{.type = CDL_UntypedCap, .obj_id = " ++ showObjID objs id ++ "}"
showCap objs (EndpointCap id badge rights) _ is_orig _ =
    "{.type = CDL_EPCap, .obj_id = " ++ showObjID objs id ++
    ", .is_orig = " ++ is_orig ++
    ", .rights = " ++ showRights rights ++
    ", .data = { .tag = CDL_CapData_Badge, .badge = " ++ show badge ++ "}}"
showCap objs (NotificationCap id badge rights) _ is_orig _ =
    "{.type = CDL_NotificationCap, .obj_id = " ++ showObjID objs id ++
    ", .is_orig = " ++ is_orig ++
    ", .rights = " ++ showRights rights ++
    ", .data = { .tag = CDL_CapData_Badge, .badge = " ++ show badge ++
    "}}"
showCap objs (ReplyCap id) _ _ _ =
    "{.type = CDL_ReplyCap, .obj_id = " ++ showObjID objs id ++ "}"
    -- XXX: Does it even make sense to give out a reply cap? How does init fake this?
showCap objs (MasterReplyCap id) _ _ _ =
    "{.type = CDL_MasterReplyCap, .obj_id = " ++ showObjID objs id ++ "}"
    -- XXX: As above.
showCap objs (CNodeCap id guard guard_size) _ is_orig _ =
    "{.type = CDL_CNodeCap, .obj_id = " ++ showObjID objs id ++
    ", .is_orig = " ++ is_orig ++
    ", .rights = seL4_AllRights, .data = CDL_CapData_MakeGuard(" ++
    show guard_size ++ ", " ++ show guard ++ ")}"
showCap objs (TCBCap id) _ is_orig _ =
    "{.type = CDL_TCBCap, .obj_id = " ++ showObjID objs id ++
    ", .is_orig = " ++ is_orig ++
    ", .rights = seL4_AllRights}"
showCap _ IRQControlCap _ _ _ = "{.type = CDL_IRQControlCap}"
showCap _ (IRQHandlerCap id) irqNode is_orig _ =
    "{.type = CDL_IRQHandlerCap, .obj_id = INVALID_OBJ_ID" ++
    ", .is_orig = " ++ is_orig ++
    ", .irq = " ++ show (lookupByValue (\x -> x == id) irqNode) ++ "}"
    -- Caps have obj_ids, or IRQs, but not both.
showCap _ (IRQIOAPICHandlerCap id) irqNode is_orig _ =
    "{.type = CDL_IRQHandlerCap, .obj_id = INVALID_OBJ_ID" ++
    ", .is_orig = " ++ is_orig ++
    ", .irq = " ++ show (lookupByValue (\x -> x == id) irqNode) ++ "}"
    -- Caps have obj_ids, or IRQs, but not both.
showCap _ (IRQMSIHandlerCap id) irqNode is_orig _ =
    "{.type = CDL_IRQHandlerCap, .obj_id = INVALID_OBJ_ID" ++
    ", .is_orig = " ++ is_orig ++
    ", .irq = " ++ show (lookupByValue (\x -> x == id) irqNode) ++ "}"
    -- Caps have obj_ids, or IRQs, but not both.
showCap objs (FrameCap id rights _ cached maybe_mapping) _ is_orig _ =
    "{.type = CDL_FrameCap, .obj_id = " ++ showObjID objs id ++
    ", .is_orig = " ++ is_orig ++
    ", .rights = " ++ showRights rights ++
    ", .vm_attribs = " ++ (if cached then "seL4_ARCH_Default_VMAttributes" else "CDL_VM_CacheDisabled") ++
    ", .mapping_container_id = " ++ case maybe_mapping of {
                                      Just (mapping_container, _) -> showObjID objs mapping_container;
                                      _ -> "INVALID_OBJ_ID"
                                    } ++
    ", .mapping_slot = " ++ case maybe_mapping of {
                              Just (_, mapping_slot) -> (show mapping_slot);
                              _ -> "0"
                            } ++ "}"
    -- FIXME: I feel like I should be doing something with the ASID data here...
showCap objs (PTCap id _) _ is_orig _ =
    "{.type = CDL_PTCap, .obj_id = " ++ showObjID objs id ++
    ", .is_orig = " ++ is_orig ++ "}"
showCap objs (PDCap id _) _ is_orig _ =
    "{.type = CDL_PDCap, .obj_id = " ++ showObjID objs id ++
    ", .is_orig = " ++ is_orig ++ "}"
showCap objs (PDPTCap id _) _ is_orig _ =
    "{.type = CDL_PDPTCap, .obj_id = " ++ showObjID objs id ++
    ", .is_orig = " ++ is_orig ++ "}"
showCap objs (PML4Cap id _) _ is_orig _ =
    "{.type = CDL_PML4Cap, .obj_id = " ++ showObjID objs id ++
    ", .is_orig = " ++ is_orig ++ "}"
showCap _ ASIDControlCap _ _ _ =
    "{.type = CDL_ASIDControlCap}"
showCap objs (ASIDPoolCap id _) _ _ _ =
    "{.type = CDL_ASIDPoolCap, .obj_id = " ++ showObjID objs id ++ "}"
showCap objs (IOPortsCap id ports) _ is_orig _ =
    "{.type = CDL_IOPortsCap, .obj_id = " ++ showObjID objs id ++
    ", .is_orig = " ++ is_orig ++
    ", .data = { .tag = CDL_CapData_Raw, .data = " ++ showPorts ports ++ "}}"
showCap objs (IOSpaceCap id) _ is_orig ms =
    "{.type = CDL_IOSpaceCap, .obj_id = " ++ showObjID objs id ++
    ", .is_orig = " ++ is_orig ++
    ", .data = { .tag = CDL_CapData_Raw, .data = " ++ showPCI dom pci ++ "}}"
    where pci = pciDevice $ fromJust $ Map.lookup id ms
          dom = domainID $ fromJust $ Map.lookup id ms
showCap objs (VCPUCap id) _ _ _ = "{.type = CDL_VCPUCap, .obj_id = " ++ showObjID objs id ++ "}"
showCap _ SchedControlCap _ _ _ =
    "{.type = CDL_SchedControlCap}"
showCap objs (SCCap id) _ is_orig _ =
    "{.type = CDL_SCCap, .obj_id = " ++ showObjID objs id ++
    ", .is_orig = " ++ is_orig ++ "}"
showCap _ x _ _ _ = assert False $
    "UNSUPPORTED CAP TYPE: " ++ show x
    -- These are not supported by the initialiser itself.

showSlots :: Map ObjID Int -> ObjID -> [(Word, Cap)] -> IRQMap -> CDT -> ObjMap Word -> String
showSlots _ _ [] _ _ _ = ""
showSlots objs obj_id (x:xs) irqNode cdt ms =
    "{" ++ show index ++ ", " ++ slot ++ "}," +++
    showSlots objs obj_id xs irqNode cdt ms
    where
        index = fst x
        slot = showCap objs (snd x) irqNode is_orig ms
        is_orig = if (Map.notMember (obj_id, index) cdt) then "true" else "false"

memberSlots :: Map ObjID Int -> ObjID -> CapMap Word -> IRQMap -> CDT -> ObjMap Word -> String
memberSlots objs obj_id slots irqNode cdt ms =
    ".slots.num = " ++ show slot_count ++ "," +++
    ".slots.slot = (CDL_CapSlot[]) {" +++
    showSlots objs obj_id (Map.toList slots) irqNode cdt ms +++
    "},"
    where
        slot_count = Map.size slots

printInit :: [Word] -> String
printInit argv =
    "{" ++ Data.List.Utils.join ", " (Data.List.Compat.map show argv) ++ "}"

showObjectFields :: Map ObjID Int -> ObjID -> KernelObject Word -> IRQMap -> CDT -> ObjMap Word -> String
showObjectFields _ _ Endpoint _ _ _ = ".type = CDL_Endpoint,"
showObjectFields _ _ Notification _ _ _ = ".type = CDL_Notification,"
showObjectFields objs obj_id (TCB slots faultEndpoint info domain argv) _ _ _ =
    ".type = CDL_TCB," +++
    ".tcb_extra = {" +++
    "#if (" ++ show ipcbuffer_addr ++ " & ((1 << 9) - 1)) != 0" +++
    "#    error \"IPC buffer not 512-byte aligned\"" +++
    "#endif" +++
    ".ipcbuffer_addr_upper_bits = " ++ show ipcbuffer_addr ++ " >> 9," +++
    ".priority = " ++ show priority ++ "," +++
    ".max_priority = " ++ show max_priority ++ "," +++
    ".criticality = " ++ show criticality ++ "," +++
    ".max_criticality = " ++ show max_criticality ++ "," +++
    ".pc = " ++ show pc ++ "," +++
    ".sp = " ++ show stack ++ "," +++
    ".elf_name = " ++ show elf_name ++ "," +++
    ".init = (const seL4_Word[])" ++ printInit argv ++ "," +++
    ".init_sz = " ++ show (length argv) ++ "," +++
    ".domain = " ++ show domain ++ "," +++
    ".fault_ep = " ++ show fault_ep ++ "," +++
    "}," +++
    memberSlots objs obj_id slots Map.empty Map.empty Map.empty -- IRQ, cdt and obj map not required
    where
        ipcbuffer_addr = case info of {Just i -> ipcBufferAddr i; _ -> 0}
        priority = case info of {Just i -> case prio i of {Just p -> p; _ -> 125}; _ -> 125}
        max_priority = case info of {Just i -> case max_prio i of {Just p -> p; _ -> 125}; _ -> 125}
        criticality = case info of {Just i -> case crit i of {Just p -> p; _ -> 125}; _ -> 125}
        max_criticality = case info of {Just i -> case max_crit i of {Just p -> p; _ -> 125}; _ -> 125}
        pc = case info of {Just i -> case ip i of {Just v -> v; _ -> 0}; _ -> 0}
        stack = case info of {Just i -> case sp i of {Just v -> v; _ -> 0}; _ -> 0}
        elf_name = case info of {Just i -> case elf i of {Just e -> e; _ -> ""}; _ -> ""}
        fault_ep = case faultEndpoint of {Just w -> w; _ -> 0}
showObjectFields objs obj_id (CNode slots sizeBits) irqNode cdt ms =
    ".type = " ++ t ++ "," +++
    ".size_bits = " ++ show sizeBits ++ "," +++
    memberSlots objs obj_id slots irqNode cdt ms
    where
        -- IRQs are represented in CapDL as 0-sized CNodes. This is fine for
        -- the model, but the initialiser needs to know what objects represent
        -- interrupts to avoid trying to create them at runtime. It's a bit of
        -- a hack to assume that any 0-sized CNode is an interrupt, but this is
        -- an illegal size for a valid CNode so everything should work out.
        t = if sizeBits == 0 then "CDL_Interrupt" else "CDL_CNode"
showObjectFields objs obj_id (IOAPICIrq slots ioapic pin level polarity) irqNode cdt ms =
    ".type = CDL_IOAPICInterrupt, " +++
    memberSlots objs obj_id slots irqNode cdt ms +++
    ".ioapicirq_extra = {" +++
        ".ioapic = " ++ show ioapic ++ "," +++
        ".ioapic_pin = " ++ show pin ++ "," +++
        ".level = " ++ show level ++ "," +++
        ".polarity = " ++ show polarity ++ "," +++
    "},"
showObjectFields objs obj_id (MSIIrq slots handle bus dev fun) irqNode cdt ms =
    ".type = CDL_MSIInterrupt, " +++
    memberSlots objs obj_id slots irqNode cdt ms +++
    ".msiirq_extra = {" +++
        ".handle = " ++ show handle ++ "," +++
        ".pci_bus = " ++ show bus ++ "," +++
        ".pci_dev = " ++ show dev ++ "," +++
        ".pci_fun = " ++ show fun ++ "," +++
    "},"
showObjectFields _ _ (Untyped size_bits paddr) _ _ _ =
    ".type = CDL_Untyped," +++
    ".size_bits = " ++ show sizeBits ++ "," +++
    ".paddr = (void*)" ++ hex (fromMaybe 0 paddr) ++ ","
    where
        sizeBits = case size_bits of {Just s -> s; _ -> -1}
showObjectFields objs obj_id (PT slots) _ _ _ =
    ".type = CDL_PT," +++
    memberSlots objs obj_id slots Map.empty Map.empty Map.empty -- IRQ, cdt and obj map not required
showObjectFields objs obj_id (PD slots) _ _ _ =
    ".type = CDL_PD," +++
    memberSlots objs obj_id slots Map.empty Map.empty Map.empty -- IRQ, cdt and obj map not required
showObjectFields objs obj_id (PDPT slots) _ _ _ =
    ".type = CDL_PDPT," +++
    memberSlots objs obj_id slots Map.empty Map.empty Map.empty -- IRQ, cdt and obj map not required
showObjectFields objs obj_id (PML4 slots) _ _ _ =
    ".type = CDL_PML4," +++
    memberSlots objs obj_id slots Map.empty Map.empty Map.empty -- IRQ, cdt and obj map not required
showObjectFields _ _ (Frame size paddr) _ _ _ =
    ".type = CDL_Frame," +++
    ".size_bits = " ++ show (logBase 2 $ fromIntegral size) ++ "," +++
    ".paddr = (void*)" ++ hex (fromMaybe 0 paddr) ++ ","
showObjectFields _ _ (IOPorts size) _ _ _ =
    ".type = CDL_IOPorts," +++
    ".size_bits = " ++ show size ++ "," -- FIXME: This doesn't seem right.
showObjectFields objs obj_id (ASIDPool slots) _ _ _ =
    ".type = CDL_ASIDPool," +++
    memberSlots objs obj_id slots Map.empty Map.empty Map.empty -- IRQ, cdt and obj map not required
showObjectFields _ _ (IODevice _ _ _) _ _ _ =
    ".type = CDL_IODevice,"
showObjectFields _ _ VCPU _ _ _ = ".type = CDL_VCPU,"
showObjectFields _ _ (SC info) _ _ _ =
    ".type = CDL_SchedContext," +++
    ".sc_extra = {" +++
        ".period = " ++ show sc_period ++ "," +++
        ".budget = " ++ show sc_budget ++ "," +++
        ".data = " ++ show sc_data ++ "," +++
    "},"
    where
    sc_period = case info of {Just i -> case period i of {Just p -> p; _ -> 0}; _ -> 0}
    sc_budget = case info of {Just i -> case budget i of {Just p -> p; _ -> 0}; _ -> 0}
    sc_data = case info of {Just i -> case scData i of {Just p -> p; _ -> 0}; _ -> 0}

showObjectFields _ _ x _ _ _ = assert False $
    "UNSUPPORTED OBJECT TYPE: " ++ show x

showObject :: Map ObjID Int -> (ObjID, KernelObject Word) -> IRQMap -> CDT -> ObjMap Word -> String
showObject objs obj irqNode cdt ms =
    "{" +++
    "#ifdef CONFIG_CAPDL_LOADER_PRINTF" +++ ".name = \"" ++ name ++ "\"," +++ "#endif" +++
    showObjectFields objs id (snd obj) irqNode cdt ms +++
    "}"
    where
        id = fst obj
        name = fst id ++ (case snd id of
            Just index -> "[" ++ show index ++ "]"
            _ -> "")

showObjects :: Map ObjID Int -> Int -> [(ObjID, KernelObject Word)] -> IRQMap -> CDT -> ObjMap Word -> String
showObjects _ _ [] _ _ _ = ""
showObjects objs counter (x:xs) irqNode cdt ms =
    "[" ++ show counter ++ "] = " ++ showObject objs x irqNode cdt ms ++ "," +++
    showObjects objs (counter + 1) xs irqNode cdt ms

sizeOf :: Arch -> KernelObject Word -> Word
sizeOf _ (Frame vmSz _) = vmSz
sizeOf _ (Untyped (Just bSz) _) = 2 ^ bSz
sizeOf IA32 (CNode _ bSz) = 16 * 2 ^ bSz
sizeOf ARM11 (CNode _ bSz) = 16 * 2 ^ bSz
sizeOf X86_64 (CNode _ bSz) = 32 * 2 ^ bSz
sizeOf _ Endpoint = 16
sizeOf IA32 Notification = 16
sizeOf ARM11 Notification = 16
sizeOf X86_64 Notification = 32
sizeOf _ ASIDPool {} = 4 * 2^10
sizeOf _ IOPT {} = 4 * 2^10
sizeOf _ IODevice {} = 1
sizeOf IA32 TCB {} = 2^10
sizeOf IA32 PD {} = 4 * 2^10
sizeOf IA32 PT {} = 4 * 2^10
sizeOf IA32 SC {} = 60
sizeOf ARM11 TCB {} = 512
sizeOf ARM11 PD {} = 16 * 2^10
sizeOf ARM11 PT {} = 2^10
sizeOf ARM11 SC {} = 60
sizeOf X86_64 TCB {} = 2^10
sizeOf X86_64 PT {} = 4 * 2^10
sizeOf X86_64 PD {} = 4 * 2^10
sizeOf X86_64 PDPT {} = 4 * 2^10
sizeOf X86_64 PML4 {} = 4 * 2^10
sizeOf X86_64 SC {} = 60
sizeOf _ _ = 0

objPaddr :: KernelObject Word -> Maybe Word
objPaddr (Frame _ paddr) = paddr
objPaddr (Untyped _ paddr) = paddr
objPaddr _ = Nothing

{- A custom sorting function for CapDL objects. We essentially want to treat
 - this is two different list of objects, that have different requirements
 - on their ordering. Objects that have a physical address are almost certainly
 - being allocated from device untypeds and need to be allocated by the capDL
 - loader in physical address order. Any other object will be allocated from
 - regular untypeds and should be in descending order of size for optimal
 - runtime allocation. But we also want to give some rudimentary finer control
 - to the user producing the input specification. For this, we sort objects
 - secondarily by their name. This means the spec creator can name their objects
 - to induce a specific ordering for identically sized objects. This is primarily
 - useful for getting physically contiguous frames.
 -}
sorter :: Arch -> (ObjID, KernelObject Word) -> (ObjID, KernelObject Word) -> Ordering
sorter arch a b =
    if has_paddr a || has_paddr b
        then paddr a `compare` paddr b
        else
            if a_size == b_size
                then fst a `compare` fst b
                else b_size `compare` a_size -- Arguments reversed for largest to smallest
    where
        a_size = sizeOf arch $ snd a
        b_size = sizeOf arch $ snd b
        has_paddr kobj = isJust (objPaddr (snd kobj))
        paddr kobj = fromMaybe 1 (objPaddr (snd kobj))

memberObjects ::  Map ObjID Int -> Arch -> [(ObjID, KernelObject Word)] -> IRQMap -> CDT ->
                  ObjMap Word -> String
memberObjects obj_ids _ objs irqNode cdt objs' =
    ".objects = (CDL_Object[]) {" +++
    showObjects obj_ids 0 objs irqNode cdt objs' +++
    "},"

-- Emit an array where each entry represents a given interrupt. Each is -1 if
-- that interrupt has no handler or else the object ID of the interrupt
-- (0-sized CNode).
memberIRQs :: Map ObjID Int -> IRQMap -> Arch -> String
memberIRQs objs irqNode _ =
    ".irqs = {" +++
    (join ", " $ Data.List.Compat.map (\k -> show $ case Map.lookup k irqNode of
        Just i -> fromJust $ Map.lookup i objs
        _ -> -1) [0..(CONFIG_CAPDL_LOADER_MAX_IRQS - 1)]) +++
    "},"

printC :: Model Word -> Idents CapName -> CopyMap -> Doc
printC (Model arch objs irqNode cdt _) _ _ =
    text $
    "/* Generated file. Your changes will be overwritten. */" +++
    "" +++
    "#include <capdl.h>" +++
    "" +++
    "#ifndef INVALID_SLOT" +++
    "#define INVALID_SLOT (-1)" +++
    "#endif" +++
    "" +++
    maxObjects objs_sz +++ -- FIXME: I suspect this is not the right list to measure.
    "" +++
    "CDL_Model capdl_spec = {" +++
    memberArch arch +++
    memberNum objs_sz +++
    memberIRQs obj_ids irqNode arch +++
    memberObjects obj_ids arch objs' irqNode cdt objs +++
    "};"
    where
        objs_sz = length $ Map.toList objs
        objs' = sortBy (sorter arch) $ Map.toList objs
        obj_ids = Map.fromList $ flip zip [0..] $ Prelude.Compat.map fst objs'
