pragma solidity >=0.8.19;

function acceptableDelta(uint256 x, uint256 y, uint256 d) pure returns (bool) {
    if (x > y) {
        return x - y <= d;
    } else {
        return y - x <= d;
    }
}
