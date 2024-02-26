// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.20;
pragma abicoder v2;

import '@cryptoalgebra/periphery/contracts/libraries/TransferHelper.sol';
import '@cryptoalgebra/periphery/contracts/interfaces/ISwapRouter.sol';

abstract contract SwapMultihop {
    // For the scope of these swap examples,
    // we will detail the design considerations when using
    // `exactInput`, `exactInputSingle`, `exactOutput`, and  `exactOutputSingle`.

    // It should be noted that for the sake of these examples, we purposefully pass in the swap router instead of inherit the swap router for simplicity.
    // More advanced example contracts will detail how to inherit the swap router safely.

    ISwapRouter public immutable swapRouter;

    // This example swaps USDC/NEW_TOKEN for single path swaps and USDC/SUBLIC/NEW_TOKEN for multi path swaps.

    address public constant USDC = 0xF41D41BcCCeD504fe9FC4625f33034AaC7a60c11;
    address public constant SUBLIC = 0xc0036c38dA44Dae61e2716D07766ab512839b874;

    constructor(ISwapRouter _swapRouter) {
        swapRouter = _swapRouter;
    }

    /// @notice swapInputMultiplePools swaps a fixed amount of USDC for a maximum possible amount of NEW_TOKEN through an intermediary SUBLIC pool.
    /// For this example, we will swap USDC to SUBLIC, then SUBLIC to NEW_TOKEN to achieve our desired output.
    /// @dev The calling address must approve this contract to spend at least `amountIn` worth of its USDC for this function to succeed.
    /// @param amountIn The amount of USDC to be swapped.
    /// @return amountOut The amount of NEW_TOKEN received after the swap.
    function swapExactInputMultihop(
        uint256 amountIn,
        address token
    ) external returns (uint256 amountOut) {
        // Transfer `amountUSDCIn` of USDC to this contract.
        TransferHelper.safeTransferFrom(USDC, msg.sender, address(this), amountIn);

        // Approve the router to spend USDC.
        TransferHelper.safeApprove(USDC, address(swapRouter), amountIn);

        // Multiple pool swaps are encoded through bytes called a `path`. A path is a sequence of token addresses that define the pools used in the swaps.
        // The format for pool encoding is (tokenIn, tokenOut/tokenIn, tokenOut) where tokenIn/tokenOut parameter is the shared token across the pools.
        // Since we are swapping USDC to SUBLIC and then SUBLIC to NEW_TOKEN the path encoding is (USDC, 0.3%, SUBLIC, 0.3%, NEW_TOKEN).
        ISwapRouter.ExactInputParams memory params =
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(USDC, SUBLIC, token),
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0
            });

        // Executes the swap.
        amountOut = swapRouter.exactInput(params);
    }

    /// @notice swapExactOutputMultihop swaps a minimum possible amount of USDC for a fixed amount of NEW_TOKEN through an intermediary pool.
    /// For this example, we want to swap USDC for NEW_TOKEN through a SUBLIC pool but we specify the desired amountOut of NEW_TOKEN. Notice how the path encoding is slightly different in for exact output swaps.
    /// @dev The calling address must approve this contract to spend its USDC for this function to succeed. As the amount of input USDC is variable,
    /// the calling address will need to approve for a slightly higher amount, anticipating some variance.
    /// @param amountOut The desired amount of NEW_TOKEN.
    /// @param amountInMaximum The maximum amount of USDC willing to be swapped for the specified amountOut of NEW_TOKEN.
    /// @return amountIn The amountIn of USDC actually spent to receive the desired amountOut.
    function swapExactOutputMultihop(
        uint256 amountOut, 
        uint256 amountInMaximum,
        address token
    ) external returns (uint256 amountIn) {
        // Transfer the specified `amountInMaximum` to this contract.
        TransferHelper.safeTransferFrom(USDC, msg.sender, address(this), amountInMaximum);
        // Approve the router to spend  `amountInMaximum`.
        TransferHelper.safeApprove(USDC, address(swapRouter), amountInMaximum);

        // The parameter path is encoded as (tokenOut, tokenIn/tokenOut, tokenIn)
        // The tokenIn/tokenOut field is the shared token between the two pools used in the multiple pool swap. In this case SUBLIC is the "shared" token.
        // For an exactOutput swap, the first swap that occurs is the swap which returns the eventual desired token.
        // In this case, our desired output token is NEW_TOKEN so that swap happpens first, and is encoded in the path accordingly.
        ISwapRouter.ExactOutputParams memory params =
            ISwapRouter.ExactOutputParams({
                path: abi.encodePacked(token, SUBLIC, USDC),
                recipient: msg.sender,
                deadline: block.timestamp,
                amountOut: amountOut,
                amountInMaximum: amountInMaximum
            });

        // Executes the swap, returning the amountIn actually spent.
        amountIn = swapRouter.exactOutput(params);

        // If the swap did not require the full amountInMaximum to achieve the exact amountOut then we refund msg.sender and approve the router to spend 0.
        if (amountIn < amountInMaximum) {
            TransferHelper.safeApprove(USDC, address(swapRouter), 0);
            TransferHelper.safeTransferFrom(USDC, address(this), msg.sender, amountInMaximum - amountIn);
        }
    }
}
