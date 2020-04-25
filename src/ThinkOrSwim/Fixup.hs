{-# LANGUAGE FlexibleContexts #-}

module ThinkOrSwim.Fixup (fixupTransaction) where

import           Control.Lens
import           Control.Monad.State
import           Data.Amount
import           Data.Ledger hiding (symbol, quantity, cost)
import qualified ThinkOrSwim.API.TransactionHistory.GetTransactions as API
import           ThinkOrSwim.Transaction
import           ThinkOrSwim.Transaction.Instances ()
import           ThinkOrSwim.Types

-- If a transaction represents an options assignment, where the closing of a
-- short option has resulted in a forced purchase or sale, factor the premium
-- from the option sale into either cost basis of the purchased shares, or the
-- capital gain/loss of the sold shares. But take into account the fact that
-- multiple lots of call option contracts may be closing, which may result in
-- the sale of multiple lots of equity.

fixupTransaction
    :: Transaction API.TransactionSubType API.Order
                    API.Transaction LotAndPL
    -> State (GainsKeeperState API.TransactionSubType API.Transaction)
            (Transaction API.TransactionSubType API.Order
                           API.Transaction LotAndPL)
fixupTransaction t | not xactOA = pure t
  where
    hasOA  = has (plLot.kind.API._OptionAssignment)
    xactOA = anyOf optionLots hasOA t
           && anyOf equityLots hasOA t

fixupTransaction t =
    t & optionLots.plLoss .~ 0
      & optionLots.plKind .~ BreakEven
      & partsOf equityLots %%~ mapM f . spreadAmounts (^.quantity) value
  where
    value = sumOf (optionLots.plLot.cost) t

    f (n, pl) = do
        let pl' = pl & cost -~ sign (pl^.quantity) n
        zoom (openTransactions.at (pl^.symbol)) $
            _Just.traverse %= \x ->
                if x == pl^.plLot then pl'^.plLot else x
        pure pl'