{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

module Examples (testExamples) where

import Data.List (intersperse)
import Data.String.Here.Interpolated
import Data.Text.Lazy (Text)
import qualified Data.Text.Lazy as TL
import Journal.Model
import Journal.Parse
import Test.Tasty
import Test.Tasty.HUnit
import Text.Megaparsec

testExamples :: TestTree
testExamples =
  testGroup
    "examples"
    [ baseline,
      realWorld
    ]

baseline :: TestTree
baseline =
  testGroup
    "baseline"
    [ testCase "journal-buy-sell-profit" journalBuySellProfit,
      testCase "journal-buy-sell-loss-buy" journalBuySellLossBuy
    ]

journalBuySellProfit :: Assertion
journalBuySellProfit = ii @--> oo
  where
    ii =
      [i|
2020-07-02 buy 100 AAPL 260.00
2020-07-03 sell 100 AAPL 300.00 fees 0.20
        |]
    oo =
      [i|
2020-07-02 00:00:00 buy 100 AAPL 260.0000 open
2020-07-03 00:00:00 sell 100 AAPL 300.0000 close fees 0.002 gain 39.998000
        |]

journalBuySellLossBuy :: Assertion
journalBuySellLossBuy = ii @--> oo
  where
    ii =
      [i|
2020-07-02 buy 100 AAPL 260.00
2020-07-03 sell 100 AAPL 240.00 fees 0.20 wash to A
2020-07-04 buy 100 AAPL 260.00 apply A 100
        |]
    oo =
      [i|
2020-07-02 00:00:00 buy 100 AAPL 260.0000 open
2020-07-03 00:00:00 sell 100 AAPL 240.0000 close fees 0.002 loss 20.002000 wash to A
2020-07-03 00:00:00 wash 100 AAPL 20.0020 fees 0.002 wash to A
2020-07-04 00:00:00 buy 100 AAPL 260.0000 open washed 20.002000 apply A 100
        |]

realWorld :: TestTree
realWorld =
  testGroup
    "real-world"
    [ testCase "zoom-history" zoomHistory
    ]

zoomHistory :: Assertion
zoomHistory = ii @--> oo
  where
    ii =
      [i|
| Trns |   Qty | Open  |    Basis |    Price | Gain ($) |    |                     |
|------+-------+-------+----------+----------+----------+----+---------------------|
| Eqty |   140 | 06/24 |  99.7792 |          |          |    |                     |
| Eqty |    10 | 06/24 |   89.785 |          |          |    |                     |
| Eqty |    30 | 06/24 |   106.68 |          |          |    |                     |
| Eqty |   170 | 06/25 |  85.8415 |          |          |    |                     |

2019-06-24 buy 140 ZM 99.7792 exempt
2019-06-24 buy 10 ZM 89.785 exempt
2019-06-24 buy 30 ZM 106.68 exempt
2019-06-25 buy 170 ZM 85.8415 exempt

2019-07-01 buy 50 ZM 85.80
| Buy  |    50 |       |          |    85.80 |          |    |                     |

2019-07-01 sell 50 ZM 86.675 fees 0.10
| Sell |    50 | 06/24 |  99.7792 |   86.673 |  -655.31 |    |                     |
| Wash |  [50] | 07/01 |          |          |   655.31 | == | 85.80 -> 98.9062    |

2019-07-02 buy 50 ZM 85.50
| Buy  |    50 |       |          |    85.50 |          |    |                     |

2019-07-03 sell 100 ZM 86.7765 fees 0.19 wash to A
| Sell |    90 | 06/24 |  99.7792 |  86.7746 | -1170.42 |    |                     |
| Wash |  [50] | 07/02 |          |          |   650.23 | == | 85.50 -> 98.5046    |
| Wash |  [40] | 07/29 |          |          |   520.19 | A. |                     |
| Sell |    10 | 06/24 |   89.785 |   86.775 |   -30.10 |    |                     |
| Wash |  [10] | 07/29 |          |          |    30.10 | A. |                     |

2019-07-03 sell 100 ZM 88.14 fees 0.20 wash to A
| Sell |    30 | 06/24 |   106.68 |   88.138 |  -556.26 |    |                     |
| Wash |  [30] | 07/29 |          |          |   556.26 | A> | 95.7852 -> 98.5516  |
| Sell |    70 | 06/25 |  85.8415 |  88.1381 |   160.76 |    |                     |

2019-07-12 sell 200 ZM 94.085 fees 0.41 wash to B
| Sell |   100 | 06/25 |  85.8415 |   94.083 |   824.15 |    |                     |
| Sell |    50 | 07/01 |  98.9062 |  94.0828 |  -241.17 |    |                     |
| Sell |    50 | 07/02 |  98.5046 |   94.083 |  -221.08 |    |                     |
| Wash |  [50] | 07/29 |          |          |   241.17 | B. |                     |
| Wash |  [50] | 07/29 |          |          |   221.08 | B> | 95.7852 -> 100.4077 |

2019-07-29 buy 500 ZM 95.7852 apply A 400 apply B 100
| Buy  |   400 |       |          |  98.5516 |          | <A |                     |
| Buy  |   100 |       |          | 100.4077 |          | <B |                     |

2019-07-29 sell 400 ZM 95.657 fees 0.84 wash 200 @ 0.1303 to C
| Sell |   400 | 07/29 |  98.5516 |  95.6549 | -1158.67 |    |                     |
| Wash | [200] | 07/30 |          |          |    26.06 | C> | 96.00 -> 96.1303    |

2019-07-29 sell 100 ZM 96.1841 fees 0.21 wash dropped
| Sell |   100 | 07/29 | 100.4077 |   96.182 |  -422.57 |    |                     |

2019-07-30 buy 200 ZM 96.00 apply C 200
| Buy  |   200 |       |          |  96.1303 |          | <C |                     |
2019-09-06 buy 100 ZM 85.97 commission 5.00
| Buy  |   100 |       |          |    86.02 |          |    |                     |

2020-02-18 sell 300 ZM 95.00 fees 0.67 wash dropped
| Sell |   200 | 07/30 | 96.1303  |   95.00  |   897.78 |    |                     |
| Sell |   100 | 09/06 | 85.9245  |   95.00  |  -226.51 |    |                     |
        |]
    oo =
      [i|
2019-06-24 00:00:00 buy 140 ZM 99.7792 open exempt
2019-06-24 00:00:00 buy 10 ZM 89.7850 open exempt
2019-06-24 00:00:00 buy 30 ZM 106.6800 open exempt
2019-06-25 00:00:00 buy 170 ZM 85.8415 open exempt
2019-07-01 00:00:00 buy 50 ZM 85.8000 open
2019-07-01 00:00:00 sell 50 ZM 86.6750 close fees 0.002 loss 13.106200
2019-07-01 00:00:00 wash 50 ZM 13.1062 washed 85.800000
2019-07-02 00:00:00 buy 50 ZM 85.5000 open
2019-07-03 00:00:00 sell 90 ZM 86.7765 close fees 0.0019 loss 13.004600 wash to A
2019-07-03 00:00:00 wash 50 ZM 13.0046 washed 85.500000
2019-07-03 00:00:00 wash 40 ZM 13.0046 fees 0.0019 wash to A
2019-07-03 00:00:00 sell 10 ZM 86.7765 close fees 0.0019 loss 3.010400 wash to A
2019-07-03 00:00:00 wash 10 ZM 3.0104 fees 0.0019 wash to A
2019-07-03 00:00:00 sell 30 ZM 88.1400 close fees 0.002 loss 18.542000 wash to A
2019-07-03 00:00:00 wash 30 ZM 18.5420 fees 0.002 wash to A
2019-07-03 00:00:00 sell 70 ZM 88.1400 close fees 0.002 gain 2.296500 wash to A
2019-07-12 00:00:00 sell 100 ZM 94.0850 close fees 0.00205 gain 8.241450 wash to B
2019-07-12 00:00:00 sell 50 ZM 94.0850 close fees 0.00205 loss 4.823250 wash to B
2019-07-12 00:00:00 wash 50 ZM 4.82325 fees 0.00205 wash to B
2019-07-12 00:00:00 sell 50 ZM 94.0850 close fees 0.00205 loss 4.421650 wash to B
2019-07-12 00:00:00 wash 50 ZM 4.42165 fees 0.00205 wash to B
2019-07-29 00:00:00 buy 400 ZM 95.7852 open washed 2.766370 apply A 400 apply B 100
2019-07-29 00:00:00 buy 100 ZM 95.7852 open washed 4.622450 apply A 400 apply B 100
2019-07-29 00:00:00 sell 400 ZM 95.6570 close fees 0.0021 loss 2.896670 wash 200 @ 0.1303 to C
2019-07-29 00:00:00 wash 400 ZM 2.89667 fees 0.0021 wash 200 @ 0.1303 to C
2019-07-29 00:00:00 sell 100 ZM 96.1841 close fees 0.0021 loss 4.225650 wash dropped
2019-07-30 00:00:00 buy 200 ZM 96.0000 open washed 0.130300 apply C 200
2019-09-06 00:00:00 buy 100 ZM 85.9700 open commission 0.05
2020-02-18 00:00:00 sell 200 ZM 95.0000 close fees 0.002233 loss 1.132533 wash dropped
2020-02-18 00:00:00 sell 100 ZM 95.0000 close fees 0.002233 gain 8.977767 wash dropped
        |]

(@-->) :: Text -> Text -> Assertion
x @--> y = do
  y' <- parseProcessPrint "" x
  trimLines y' @?= trimLines y
  where
    trimLines =
      TL.concat
        . intersperse "\n"
        . map TL.strip
        . TL.splitOn "\n"
        . TL.strip
    parseProcessPrint :: MonadFail m => FilePath -> Text -> m Text
    parseProcessPrint path journal = do
      actions <- case parse parseJournal path journal of
        Left e -> fail $ errorBundlePretty e
        Right res -> pure res
      case processJournal actions of
        Left err ->
          error $ "Error processing journal " ++ path ++ ": " ++ show err
        Right j -> pure $ printJournal False j
