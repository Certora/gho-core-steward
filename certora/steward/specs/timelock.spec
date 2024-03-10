

methods {
    /*    
    function _.updateGsmExposureCap(uint128) external => NONDET;
    function _.getExposureCap() external => NONDET;
    
    function _.updateExposureCap(uint128) external => NONDET;
    function _.getFacilitatorBucket(address) external => NONDET;
    function _.setFacilitatorBucketCapacity(address,uint128) external => NONDET;
    function _.getReserveData(address) external => NONDET;
    */


    function _.getPool() external => NONDET;
    function _.getConfiguration(address) external => NONDET;
    function _.getPoolConfigurator() external => NONDET;
    

    function _.getBorrowCap(DataTypes.ReserveConfigurationMap memory) internal =>
        getBorrowCap_func() expect uint256 ;
    function _.setBorrowCap(address token, uint256 newCap) external =>
        setBorrowCap_func(token,newCap) expect void ALL;


    //    function _.getBaseVariableBorrowRate() external =>
    //  ;
    //function _.setReserveInterestRateStrategyAddress(address,address) external =>;

    function owner() external returns (address) envfree;
    function getGhoTimelocks() external returns (IGhoStewardV2.GhoDebounce) envfree;
    function getGsmTimelocks(address) external returns (IGhoStewardV2.GsmDebounce) envfree;
    function MINIMUM_DELAY() external returns uint256 envfree;
    function RISK_COUNCIL() external returns address envfree;
}

/*
ghost uint256 BorrowRate_gst {
    axiom BorrowRate_gst <= 10^27;
}

function getBorrowRate_func() returns uint256 {
    return BorrowRate_gst;
}

function setBorrowRate_func(address token, uint256 newCap) {
    BorrowRate_gst = newCap;
    }*/



ghost uint256 getBorrowCap_gst {
    axiom 1==1;
}

function getBorrowCap_func() returns uint256 {
    return getBorrowCap_gst;
}

function setBorrowCap_func(address token, uint256 newCap) {
    getBorrowCap_gst = newCap;
}




/* =================================================================================
   updateGhoBorrowCap
   ================================================================================*/
rule ghoBorrowCapLastUpdate__updated_only_by_updateGhoBorrowCap(method f) {
    env e; calldataarg args;

    uint40 ghoBorrowCapLastUpdate_before = getGhoTimelocks().ghoBorrowCapLastUpdate;
    f(e,args);
    uint40 ghoBorrowCapLastUpdate_after = getGhoTimelocks().ghoBorrowCapLastUpdate;

    assert (ghoBorrowCapLastUpdate_after != ghoBorrowCapLastUpdate_before) =>
        f.selector == sig:updateGhoBorrowCap(uint256).selector;
}

rule updateGhoBorrowCap_update_correctly__ghoBorrowCapLastUpdate() {
    env e;  uint256 newBorrowCap;
    updateGhoBorrowCap(e,newBorrowCap);
    assert getGhoTimelocks().ghoBorrowCapLastUpdate == require_uint40(e.block.timestamp);
}

rule updateGhoBorrowCap_timelock() {
    uint40 ghoBorrowCapLastUpdate_before = getGhoTimelocks().ghoBorrowCapLastUpdate;
    env e;  uint256 newBorrowCap;
    updateGhoBorrowCap(e,newBorrowCap);

    assert to_mathint(e.block.timestamp) > ghoBorrowCapLastUpdate_before + MINIMUM_DELAY();
}


/* =================================================================================
   updateGhoBorrowRate
   ================================================================================*/
rule ghoBorrowRateLastUpdate__updated_only_by_updateGhoBorrowRate(method f) {
    env e; calldataarg args;

    uint40 ghoBorrowRateLastUpdate_before = getGhoTimelocks().ghoBorrowRateLastUpdate;
    f(e,args);
    uint40 ghoBorrowRateLastUpdate_after = getGhoTimelocks().ghoBorrowRateLastUpdate;

    assert (ghoBorrowRateLastUpdate_after != ghoBorrowRateLastUpdate_before) =>
        f.selector == sig:updateGhoBorrowRate(uint256).selector;
}

rule updateGhoBorrowRate_update_correctly__ghoBorrowRateLastUpdate() {
    env e;  uint256 newBorrowRate;
    updateGhoBorrowRate(e,newBorrowRate);
    assert getGhoTimelocks().ghoBorrowRateLastUpdate == require_uint40(e.block.timestamp);
}

rule updateGhoBorrowRate_timelock() {
    uint40 ghoBorrowRateLastUpdate_before = getGhoTimelocks().ghoBorrowRateLastUpdate;
    env e;  uint256 newBorrowRate;
    updateGhoBorrowRate(e,newBorrowRate);

    assert to_mathint(e.block.timestamp) > ghoBorrowRateLastUpdate_before + MINIMUM_DELAY();
}



/* =================================================================================
   updateGsmExposureCap
   ================================================================================*/
rule gsmExposureCapLastUpdated__updated_only_by_updateGsmExposureCap(method f) {
    env e; calldataarg args;
    address gsm;

    uint40 gsmExposureCapLastUpdated_before = getGsmTimelocks(gsm).gsmExposureCapLastUpdated;
    f(e,args);
    uint40 gsmExposureCapLastUpdated_after = getGsmTimelocks(gsm).gsmExposureCapLastUpdated;

    assert (gsmExposureCapLastUpdated_after != gsmExposureCapLastUpdated_before) =>
        f.selector == sig:updateGsmExposureCap(address,uint128).selector;
}

rule updateGsmExposureCap_update_correctly__gsmExposureCapLastUpdated() {
    env e;  address gsm;   uint128 newExposureCap;
    updateGsmExposureCap(e,gsm, newExposureCap);
    assert getGsmTimelocks(gsm).gsmExposureCapLastUpdated == require_uint40(e.block.timestamp);
}

rule updateGsmExposureCap_timelock() {
    env e;  address gsm;   uint128 newExposureCap;
    uint40 gsmExposureCapLastUpdated_before = getGsmTimelocks(gsm).gsmExposureCapLastUpdated;
    updateGsmExposureCap(e,gsm, newExposureCap);

    assert to_mathint(e.block.timestamp) > gsmExposureCapLastUpdated_before + MINIMUM_DELAY();
}



/* =================================================================================
   updateGsmBuySellFees
   ================================================================================*/
rule gsmFeeStrategyLastUpdated__updated_only_by_updateGsmBuySellFees(method f) {
    env e; calldataarg args;
    address gsm;

    uint40 gsmFeeStrategyLastUpdated_before = getGsmTimelocks(gsm).gsmFeeStrategyLastUpdated;
    f(e,args);
    uint40 gsmFeeStrategyLastUpdated_after = getGsmTimelocks(gsm).gsmFeeStrategyLastUpdated;

    assert (gsmFeeStrategyLastUpdated_after != gsmFeeStrategyLastUpdated_before) =>
        f.selector == sig:updateGsmBuySellFees(address,uint256,uint256).selector;
}

rule updateGsmBuySellFees_update_correctly__gsmFeeStrategyLastUpdated() {
    env e;  address gsm;  uint256 buyFee;  uint256 sellFee;
    updateGsmBuySellFees(e,gsm, buyFee, sellFee);
    assert getGsmTimelocks(gsm).gsmFeeStrategyLastUpdated == require_uint40(e.block.timestamp);
}

rule updateGsmBuySellFees_timelock() {
    env e;  address gsm;  uint256 buyFee;  uint256 sellFee;
    uint40 gsmFeeStrategyLastUpdated_before = getGsmTimelocks(gsm).gsmFeeStrategyLastUpdated;
    updateGsmBuySellFees(e,gsm, buyFee, sellFee);

    assert to_mathint(e.block.timestamp) > gsmFeeStrategyLastUpdated_before + MINIMUM_DELAY();
}




rule only_RISK_COUNCIL_can_call__updateFacilitatorBucketCapacity() {
    env e;  address facilitator;  uint128 newBucketCapacity;

    updateFacilitatorBucketCapacity(e,facilitator,newBucketCapacity);
    assert (e.msg.sender==RISK_COUNCIL());
}
rule only_RISK_COUNCIL_can_call__updateGhoBorrowCap() {
    env e;  uint256 newBorrowCap;

    updateGhoBorrowCap(e,newBorrowCap);
    assert (e.msg.sender==RISK_COUNCIL());
}
rule only_RISK_COUNCIL_can_call__updateGhoBorrowRate() {
    env e;  uint256 newBorrowRate;

    updateGhoBorrowRate(e,newBorrowRate);
    assert (e.msg.sender==RISK_COUNCIL());
}
rule only_RISK_COUNCIL_can_call__updateGsmExposureCap() {
    env e;  address gsm;  uint128 newExposureCap;

    updateGsmExposureCap(e,gsm,newExposureCap);
    assert (e.msg.sender==RISK_COUNCIL());
}
rule only_RISK_COUNCIL_can_call__updateGsmBuySellFees() {
    env e;  address gsm;  uint256 buyFee;  uint256 sellFee;


    updateGsmBuySellFees(e,gsm,buyFee,sellFee);
    assert (e.msg.sender==RISK_COUNCIL());
}

rule only_RISK_COUNCIL_can_call__setControlledFacilitator() {
    env e;
    address[] facilitatorList;
    bool approve;

    setControlledFacilitator(e,facilitatorList,approve);
    assert (e.msg.sender==owner());
}



rule updateGhoBorrowCap__correctness() {
    env e;  uint256 newBorrowCap;
    uint256 borrow_cap_before = getBorrowCap_gst;
    updateGhoBorrowCap(e,newBorrowCap);
    uint256 borrow_cap_after = getBorrowCap_gst;
    
    assert borrow_cap_before <= borrow_cap_after && to_mathint(borrow_cap_after) <= 2*borrow_cap_before;
}
