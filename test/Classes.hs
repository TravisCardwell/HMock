{-# LANGUAGE CPP #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

module Classes where

import Control.DeepSeq (NFData (rnf))
import Control.Exception (evaluate)
import Control.Monad.Trans (MonadIO, liftIO)
import Data.Default (Default (def))
import Data.Dynamic (Typeable)
import Data.Kind (Type)
import Language.Haskell.TH.Syntax hiding (Type)
import QuasiMock ( Action(..), Matcher(..) )
import Test.HMock
import Test.HMock.TH
import Test.Hspec
import Util.TH (deriveRecursive, reifyInstancesStatic, reifyStatic)

#if !MIN_VERSION_base(4, 13, 0)
import Control.Monad.Fail (MonadFail)
#endif

#if MIN_VERSION_template_haskell(2, 16, 0)
-- Pre-define low-level instance to prevent deriveRecursive from trying.
instance NFData Bytes where rnf = undefined
#endif

deriveRecursive (Just AnyclassStrategy) ''NFData ''Dec

class MonadSimple m where
  simple :: String -> m ()

makeMockable ''MonadSimple

simpleTests :: SpecWith ()
simpleTests = describe "MonadSimple" $ do
  it "generates mock impl" $
    example $ do
      decs <- runMockT $ do
        expectAny $ QReify ''MonadSimple |-> $(reifyStatic ''MonadSimple)

        runQ (makeMockable ''MonadSimple)
      evaluate (rnf decs)

  it "doesn't require unnecessary extensions for simple cases" $
    example . runMockT $ do
      expectAny $ QReify ''MonadSimple |-> $(reifyStatic ''MonadSimple)
      expectAny $ QIsExtEnabled ScopedTypeVariables |-> False
      expectAny $ QIsExtEnabled RankNTypes |-> False

      _ <- runQ (makeMockable ''MonadSimple)
      return ()

  it "fails when GADTs is disabled" $
    example $ do
      let missingGADTs = runMockT $ do
            expectAny $ QIsExtEnabled GADTs |-> False
            expect $ QReport_ anything (hasSubstr "Please enable GADTs") |-> ()

            _ <- runQ (makeMockable ''MonadSimple)
            return ()

      missingGADTs `shouldThrow` anyIOException

  it "fails when TypeFamilies is disabled" $
    example $ do
      let missingTypeFamilies = runMockT $ do
            expectAny $ QIsExtEnabled TypeFamilies |-> False
            expect $
              QReport_ anything (hasSubstr "Please enable TypeFamilies") |-> ()

            _ <- runQ (makeMockable ''MonadSimple)
            return ()

      missingTypeFamilies `shouldThrow` anyIOException

  it "fails when DataKinds is disabled" $
    example $ do
      let missingDataKinds = runMockT $ do
            expectAny $ QIsExtEnabled DataKinds |-> False
            expect $
              QReport_ anything (hasSubstr "Please enable DataKinds") |-> ()

            _ <- runQ (makeMockable ''MonadSimple)
            return ()

      missingDataKinds `shouldThrow` anyIOException

  it "fails when FlexibleInstances is disabled" $
    example $ do
      let missingDataKinds = runMockT $ do
            expectAny $ QIsExtEnabled FlexibleInstances |-> False
            expect $
              QReport_ anything (hasSubstr "Please enable FlexibleInstances")
                |-> ()

            _ <- runQ (makeMockable ''MonadSimple)
            return ()

      missingDataKinds `shouldThrow` anyIOException

  it "fails when MultiParamTypeClasses is disabled" $
    example $ do
      let missingDataKinds = runMockT $ do
            expectAny $ QIsExtEnabled MultiParamTypeClasses |-> False
            expect $
              QReport_
                anything
                (hasSubstr "Please enable MultiParamTypeClasses")
                |-> ()

            _ <- runQ (makeMockable ''MonadSimple)
            return ()

      missingDataKinds `shouldThrow` anyIOException

  it "fails when too many params are given" $
    example $ do
      let tooManyParams = runMockT $ do
            expectAny $ QReify ''MonadSimple |-> $(reifyStatic ''MonadSimple)
            expect $
              QReport_ anything (hasSubstr "is applied to too many arguments")
                |-> ()

            _ <- runQ (makeMockableType [t|MonadSimple IO|])
            return ()

      tooManyParams `shouldThrow` anyIOException

  it "is mockable" $
    example $ do
      let success = runMockT $ do
            expect $ Simple "foo" |-> ()
            simple "foo"

          failure = runMockT $ do
            expect $ Simple "foo" |-> ()
            simple "bar"

      success
      failure `shouldThrow` anyException

class MonadSuffix m where
  suffix :: String -> m ()

makeMockableWithOptions def {mockSuffix = "Blah"} ''MonadSuffix

suffixTests :: SpecWith ()
suffixTests = describe "MonadSuffix" $ do
  it "generates mock impl" $
    example $ do
      decs <- runMockT $ do
        expectAny $ QReify ''MonadSuffix |-> $(reifyStatic ''MonadSuffix)

        runQ (makeMockableWithOptions def {mockSuffix = "Blah"} ''MonadSuffix)
      evaluate (rnf decs)

  it "is mockable" $
    example $ do
      let success = runMockT $ do
            expect $ SuffixBlah "foo" |-> ()
            suffix "foo"

          failure = runMockT $ do
            expect $ SuffixBlah "foo" |-> ()
            suffix "bar"

      success
      failure `shouldThrow` anyException

class MonadWithSetup m where
  withSetup :: m String

makeMockable ''MonadWithSetup

instance MockableSetup MonadWithSetup where
  setupMockable _ = do
    byDefault $ WithSetup |-> "custom default"

setupTests :: SpecWith ()
setupTests = describe "MonadWithSetup" $ do
  it "generates mock impl" $ do
    example $ do
      decs <- runMockT $ do
        expectAny $ QReify ''MonadWithSetup |-> $(reifyStatic ''MonadWithSetup)

        runQ (makeMockable ''MonadWithSetup)
      evaluate (rnf decs)

  it "returns the customized default value" $ do
    example $
      runMockT $ do
        expectAny WithSetup

        result <- withSetup
        liftIO (result `shouldBe` "custom default")

class SuperClass (m :: Type -> Type)

instance SuperClass m

class (SuperClass m, Monad m, Typeable m) => MonadSuper m where
  withSuper :: m ()

makeMockable ''MonadSuper

superTests :: SpecWith ()
superTests = describe "MonadSuper" $ do
  it "generated mock impl" $
    example $ do
      decs <- runMockT $ do
        expectAny $ QReify ''MonadSuper |-> $(reifyStatic ''MonadSuper)
        expectAny $
          QReifyInstances_
            (eq ''SuperClass)
            $(qMatch [p|[AppT (ConT (Name (OccName "MockT") _)) (VarT _)]|])
            |-> $( do
                     v <- runQ (newName "m")
                     reifyInstancesStatic
                       ''SuperClass
                       [AppT (ConT ''MockT) (VarT v)]
                 )

        runQ (makeMockable ''MonadSuper)
      evaluate (rnf decs)

  it "is mockable" $
    example $ do
      let success = runMockT $ do
            expect $ WithSuper |-> ()
            withSuper

          failure = runMockT withSuper

      success
      failure `shouldThrow` anyException

class MonadMPTC a m where
  mptc :: a -> m ()
  mptcList :: [a] -> m ()

makeMockable ''MonadMPTC

mptcTests :: SpecWith ()
mptcTests = describe "MonadMPTC" $ do
  it "generates mock impl" $
    example $ do
      decs <- runMockT $ do
        expectAny $ QReify ''MonadMPTC |-> $(reifyStatic ''MonadMPTC)

        runQ (makeMockable ''MonadMPTC)
      evaluate (rnf decs)

  it "is mockable" $
    example $ do
      let success = runMockT $ do
            expect $ Mptc "foo" |-> ()
            mptc "foo"

          failure = runMockT $ do
            expect $ Mptc "foo" |-> ()
            mptc "bar"

      success
      failure `shouldThrow` anyException

class MonadFDSpecialized a m | m -> a where
  fdSpecialized :: a -> m a

makeMockableType [t|MonadFDSpecialized String|]

fdSpecializedTests :: SpecWith ()
fdSpecializedTests = describe "MonadFDSpecialized" $ do
  it "generates mock impl" $
    example $ do
      decs <- runMockT $ do
        expectAny $
          QReify ''MonadFDSpecialized
            |-> $(reifyStatic ''MonadFDSpecialized)

        runQ (makeMockableType [t|MonadFDSpecialized String|])
      evaluate (rnf decs)

  it "is mockable" $
    example $ do
      let success = runMockT $ do
            expect $ FdSpecialized "foo" |-> "bar"
            r <- fdSpecialized "foo"
            liftIO $ r `shouldBe` "bar"

          failure = runMockT $ do
            expect $ FdSpecialized "foo" |-> "bar"
            fdSpecialized "bar"

      success
      failure `shouldThrow` anyException

class MonadFDGeneral a m | m -> a where
  fdGeneral :: a -> m a

deriveMockable ''MonadFDGeneral

newtype MyBase m a = MyBase {runMyBase :: m a}
  deriving newtype (Functor, Applicative, Monad, MonadIO)

instance
  (MonadIO m, Typeable m) =>
  MonadFDGeneral String (MockT (MyBase m))
  where
  fdGeneral x = mockMethod (FdGeneral x)

fdGeneralTests :: SpecWith ()
fdGeneralTests = describe "MonadFDGeneral" $ do
  it "generates mock impl" $
    example $ do
      decs <- runMockT $ do
        expectAny $ QReify ''MonadFDGeneral |-> $(reifyStatic ''MonadFDGeneral)

        runQ (deriveMockable ''MonadFDGeneral)
      evaluate (rnf decs)

  it "is mockable" $
    example $ do
      let success = runMyBase . runMockT $ do
            expect $ FdGeneral "foo" |-> "bar"
            r <- fdGeneral "foo"
            liftIO $ r `shouldBe` "bar"

          failure = runMyBase . runMockT $ do
            expect $ FdGeneral "foo" |-> "bar"
            fdGeneral "bar"

      success
      failure `shouldThrow` anyException

class MonadFDMixed a b c d m | m -> a b c d where
  fdMixed :: a -> b -> c -> m d

deriveMockableType [t|MonadFDMixed String Int|]
deriveTypeForMockT [t|MonadFDMixed String Int String String|]

fdMixedTests :: SpecWith ()
fdMixedTests = describe "MonadFDMixed" $ do
  it "generates mock impl" $
    example . runMockT $ do
      expectAny $ QReify ''MonadFDMixed |-> $(reifyStatic ''MonadFDMixed)

      decs1 <- runQ (deriveMockableType [t|MonadFDMixed String Int|])
      decs2 <-
        runQ (deriveTypeForMockT [t|MonadFDMixed String Int String Int|])
      _ <- liftIO $ evaluate (rnf (decs1 ++ decs2))
      return ()

  it "is mockable" $
    example $ do
      let success = runMockT $ do
            expect $ FdMixed "foo" 1 "bar" |-> "qux"
            r <- fdMixed "foo" 1 "bar"
            liftIO $ r `shouldBe` "qux"

          failure = runMockT $ do
            expect $ FdMixed "foo" 1 "bar" |-> "qux"
            _ <- fdMixed "bar" 1 "foo"
            return ()

      success
      failure `shouldThrow` anyException

class MonadPolyArg m where
  polyArg :: Enum a => String -> a -> b -> m ()

makeMockable ''MonadPolyArg

polyArgTests :: SpecWith ()
polyArgTests = describe "MonadPolyArg" $ do
  it "generates mock impl" $
    example $ do
      decs <- runMockT $ do
        expectAny $ QReify ''MonadPolyArg |-> $(reifyStatic ''MonadPolyArg)

        runQ (makeMockable ''MonadPolyArg)
      evaluate (rnf decs)

  it "fails without ScopedTypeVariables" $
    example $ do
      let missingScopedTypeVariables = runMockT $ do
            expectAny $
              QReify ''MonadPolyArg |-> $(reifyStatic ''MonadPolyArg)
            expectAny $ QIsExtEnabled ScopedTypeVariables |-> False
            expect $
              QReport_ anything (hasSubstr "Please enable ScopedTypeVariables")
                |-> ()

            _ <- runQ (makeMockable ''MonadPolyArg)
            return ()

      missingScopedTypeVariables `shouldThrow` anyException

  it "fails without RankNTypes" $
    example $ do
      let missingRankNTypes = runMockT $ do
            expectAny $ QReify ''MonadPolyArg |-> $(reifyStatic ''MonadPolyArg)
            expectAny $ QIsExtEnabled RankNTypes |-> False
            expect $
              QReport_ anything (hasSubstr "Please enable RankNTypes") |-> ()

            _ <- runQ (makeMockable ''MonadPolyArg)
            return ()

      missingRankNTypes `shouldThrow` anyException

  it "is mockable" $
    example $ do
      let success = runMyBase . runMockT $ do
            expect $
              PolyArg_ (eq "foo") (with fromEnum (eq 1)) anything |-> ()
            polyArg "foo" (toEnum 1 :: Bool) "hello"

          failure = runMyBase . runMockT $ do
            expect $
              PolyArg_ (eq "foo") (with fromEnum (eq 1)) anything |-> ()
            polyArg "foo" (toEnum 2 :: Bool) "hello"

      success
      failure `shouldThrow` anyException

class MonadUnshowableArg m where
  unshowableArg :: (Int -> Int) -> m ()

makeMockable ''MonadUnshowableArg

unshowableArgTests :: SpecWith ()
unshowableArgTests = describe "MonadUnshowableArg" $ do
  it "generates mock impl" $
    example $ do
      decs <- runMockT $ do
        expectAny $
          QReify ''MonadUnshowableArg |-> $(reifyStatic ''MonadUnshowableArg)

        runQ (makeMockable ''MonadUnshowableArg)
      evaluate (rnf decs)

  it "is mockable" $
    example $ do
      let success = runMyBase . runMockT $ do
            expect $ UnshowableArg_ anything |-> ()
            unshowableArg (+ 1)

          failure = runMyBase . runMockT $ do
            expect $ UnshowableArg_ anything |-> ()

            unshowableArg (+ 1)
            unshowableArg (+ 1)

      success
      failure `shouldThrow` anyException

class MonadInArg m where
  monadInArg :: (Int -> m ()) -> m ()

makeMockable ''MonadInArg

monadInArgTests :: SpecWith ()
monadInArgTests = describe "MonadInArg" $ do
  it "generates mock impl" $
    example $ do
      decs <- runMockT $ do
        expectAny $ QReify ''MonadInArg |-> $(reifyStatic ''MonadInArg)

        runQ (makeMockable ''MonadInArg)
      evaluate (rnf decs)

  it "is mockable" $
    example $ do
      let success = runMyBase . runMockT $ do
            expect $ MonadInArg_ anything |-> ()
            monadInArg (const (return ()))

          failure = runMyBase . runMockT $ do
            expect $ UnshowableArg_ anything |-> ()

            monadInArg (const (return ()))
            monadInArg (const (return ()))

      success
      failure `shouldThrow` anyException

class MonadExtraneousMembers m where
  data SomeDataType m
  favoriteNumber :: SomeDataType m -> Int
  wrongMonad :: Monad n => m Int -> n Int
  polyResult :: a -> m a
  nestedRankN :: ((forall a. a -> Bool) -> Bool) -> m ()

  mockableMethod :: Int -> m ()

deriveMockable ''MonadExtraneousMembers

instance (Typeable m, MonadIO m) => MonadExtraneousMembers (MockT m) where
  data SomeDataType (MockT m) = SomeCon
  favoriteNumber SomeCon = 42
  wrongMonad _ = return 42
  polyResult = return
  nestedRankN _ = return ()

  mockableMethod a = mockMethod (MockableMethod a)

extraneousMembersTests :: SpecWith ()
extraneousMembersTests = describe "MonadExtraneousMembers" $ do
  it "generates mock impl" $
    example $ do
      decs <- runMockT $ do
        expectAny $
          QReify ''MonadExtraneousMembers
            |-> $(reifyStatic ''MonadExtraneousMembers)

        runQ (deriveMockable ''MonadExtraneousMembers)
      evaluate (rnf decs)

  it "warns about non-methods" $
    example $ do
      decs <- runMockT $ do
        expectAny $
          QReify ''MonadExtraneousMembers
            |-> $(reifyStatic ''MonadExtraneousMembers)
        expect $ QReport False "A non-value member cannot be mocked." |-> ()
        expect $
          QReport False "favoriteNumber can't be mocked: non-monadic result."
            |-> ()
        expect $
          QReport
            False
            "wrongMonad can't be mocked: return value in wrong monad."
            |-> ()
        expect $
          QReport False "polyResult can't be mocked: polymorphic return value."
            |-> ()
        expect $
          QReport
            False
            "nestedRankN can't be mocked: rank-n types nested in arguments."
            |-> ()

        runQ
          ( deriveMockableWithOptions
              def {mockVerbose = True}
              ''MonadExtraneousMembers
          )
      evaluate (rnf decs)

  it "fails to derive MockT when class has extra methods" $
    example $ do
      let unmockableMethods = runMockT $ do
            expectAny $
              QReify ''MonadExtraneousMembers
                |-> $(reifyStatic ''MonadExtraneousMembers)
            expect $
              QReport_ anything (hasSubstr "has unmockable methods") |-> ()

            _ <- runQ (makeMockable ''MonadExtraneousMembers)
            return ()

      unmockableMethods `shouldThrow` anyIOException

  it "is mockable" $
    example $ do
      let success = runMyBase . runMockT $ do
            expect $ MockableMethod 42 |-> ()
            mockableMethod (favoriteNumber (SomeCon @(MockT IO)))

          failure = runMyBase . runMockT $ do
            expect $ MockableMethod 42 |-> ()
            mockableMethod 12

      success
      failure `shouldThrow` anyException

class MonadRankN m where
  rankN :: (forall a. a -> Bool) -> Bool -> m ()

makeMockable ''MonadRankN

rankNTests :: SpecWith ()
rankNTests = describe "MonadRankN" $ do
  it "generates mock impl" $
    example $ do
      decs <- runMockT $ do
        expectAny $ QReify ''MonadRankN |-> $(reifyStatic ''MonadRankN)

        runQ (deriveMockable ''MonadRankN)
      evaluate (rnf decs)

  it "is mockable" $
    example $ do
      let success = runMockT $ do
            expect $ RankN_ anything (eq True) |-> ()
            rankN (const True) True

          failure = runMockT $ do
            expect $ RankN_ anything (eq True) |-> ()
            rankN (const True) False

      success
      failure `shouldThrow` anyException

-- | Type with no Default instance.
data NoDefault = NoDefault

class MonadStrict m where
  strictUnit :: m ()
  strictInt :: m Int
  strictString :: m String
  strictMaybe :: m (Maybe Bool)
  strictNoDefault :: m NoDefault

makeMockableWithOptions def {mockLax = False} ''MonadStrict

class MonadLax m where
  laxUnit :: m ()
  laxInt :: m Int
  laxString :: m String
  laxMaybe :: m (Maybe Bool)
  laxNoDefault :: m NoDefault

makeMockableWithOptions def {mockLax = True} ''MonadLax

class MonadMixedLaxity m where
  strictMethod :: m ()
  laxMethod :: m ()
  defaultlessMethod :: m ()
  laxDefaultlessMethod :: m ()

deriveMockable ''MonadMixedLaxity

instance (Typeable m, MonadIO m) => MonadMixedLaxity (MockT m) where
  laxMethod = mockLaxMethod LaxMethod
  strictMethod = mockMethod StrictMethod
  defaultlessMethod = mockDefaultlessMethod DefaultlessMethod
  laxDefaultlessMethod = mockLaxDefaultlessMethod LaxDefaultlessMethod

laxityTests :: SpecWith ()
laxityTests = do
  describe "MonadStrict" $ do
    it "generates mock impl" $
      example $ do
        decs <- runMockT $ do
          expectAny $ QReify ''MonadStrict |-> $(reifyStatic ''MonadStrict)
          expectAny $
            QReifyInstances ''Default [ConT ''NoDefault]
              |-> $(reifyInstancesStatic ''Default [ConT ''NoDefault])

          runQ (makeMockableWithOptions def {mockLax = False} ''MonadStrict)
        evaluate (rnf decs)

    it "fails when there's an unexpected method" $
      example $ runMockT strictUnit `shouldThrow` anyException

    it "succeeds when there's an expected method with default response" $
      example $ do
        result <- runMockT $ do
          expect StrictUnit
          expect StrictInt
          expect StrictString
          expect StrictMaybe

          (,,,)
            <$> strictUnit
            <*> strictInt
            <*> strictString
            <*> strictMaybe

        result `shouldBe` ((), 0, "", Nothing)

    it "overrides default when response is specified" $
      example $ do
        result <- runMockT $ do
          expect StrictInt
          expect $ StrictString |-> "non-default"

          (,)
            <$> strictInt
            <*> strictString

        result `shouldBe` (0, "non-default")

    it "returns undefined when response isn't given for defaultless method" $
      example $ do
        let test = runMockT $ do
              expect StrictNoDefault
              strictNoDefault
        _ <- test
        (test >>= evaluate) `shouldThrow` anyException

  describe "MonadLax" $ do
    it "generates mock impl" $
      example $ do
        decs <- runMockT $ do
          expectAny $ QReify ''MonadLax |-> $(reifyStatic ''MonadLax)
          expectAny $
            QReifyInstances ''Default [ConT ''NoDefault]
              |-> $(reifyInstancesStatic ''Default [ConT ''NoDefault])

          runQ (makeMockableWithOptions def {mockLax = True} ''MonadLax)
        evaluate (rnf decs)

    it "succeeds when unexpected methods are called" $
      example $ do
        result <- runMockT $ do
          (,,,)
            <$> laxUnit
            <*> laxInt
            <*> laxString
            <*> laxMaybe

        result `shouldBe` ((), 0, "", Nothing)

  describe "MonadMixedLaxity" $ do
    it "generates mock impl" $
      example $ do
        decs <- runMockT $ do
          expectAny $
            QReify ''MonadMixedLaxity |-> $(reifyStatic ''MonadMixedLaxity)

          runQ (deriveMockable ''MonadMixedLaxity)
        evaluate (rnf decs)

    it "responds appropriately to unexpected methods" $
      example $ do
        let strict = runMockT strictMethod
        let lax = runMockT laxMethod
        let strictND = runMockT defaultlessMethod
        let laxND = runMockT laxDefaultlessMethod

        strict `shouldThrow` anyException

        lax >>= evaluate

        strictND `shouldThrow` anyException

        laxND
        (laxND >>= evaluate) `shouldThrow` anyException

    it "responds appropriately to expected methods with no response" $
      example $ do
        let strict = runMockT $ expect StrictMethod >> strictMethod
        let lax = runMockT $ expect LaxMethod >> laxMethod
        let strictND = runMockT $ expect DefaultlessMethod >> defaultlessMethod
        let laxND = runMockT $ expect LaxDefaultlessMethod >> laxDefaultlessMethod

        strict >>= evaluate

        lax >>= evaluate

        strictND
        (strictND >>= evaluate) `shouldThrow` anyException

        laxND
        (laxND >>= evaluate) `shouldThrow` anyException

    it "responds appropriately to expected methods with response" $
      example $ do
        let strict = runMockT $ expect (StrictMethod |-> ()) >> strictMethod
        let lax = runMockT $ expect (LaxMethod |-> ()) >> laxMethod
        let strictND =
              runMockT $
                expect (DefaultlessMethod |-> ()) >> defaultlessMethod
        let laxND =
              runMockT $
                expect (LaxDefaultlessMethod |-> ()) >> laxDefaultlessMethod

        strict >>= evaluate
        lax >>= evaluate
        strictND >>= evaluate
        laxND >>= evaluate

class MonadNestedNoDef m where
  nestedNoDef :: m (NoDefault, String)

$(return []) -- Hack to get types into the TH environment.

nestedNoDefTests :: SpecWith ()
nestedNoDefTests = describe "MonadNestedNoDef" $ do
  it "generates mock impl" $
    example $ do
      decs <- runMockT $ do
        expectAny $
          QReify ''MonadNestedNoDef |-> $(reifyStatic ''MonadNestedNoDef)
        expectAny $
          QReifyInstances
            ''Default
            [AppT (AppT (TupleT 2) (ConT ''NoDefault)) (ConT ''String)]
            |-> $( reifyInstancesStatic
                     ''Default
                     [AppT (AppT (TupleT 2) (ConT ''NoDefault)) (ConT ''String)]
                 )
        expectAny $
          QReifyInstances ''Default [ConT ''NoDefault]
            |-> $(reifyInstancesStatic ''Default [ConT ''NoDefault])

        runQ (makeMockable ''MonadNestedNoDef)
      evaluate (rnf decs)

class ClassWithNoParams

$(return []) -- Hack to get types into the TH environment.

errorTests :: SpecWith ()
errorTests = describe "errors" $ do
  it "fails when given a type instead of a class" $
    example $ do
      let wrongKind = runMockT $ do
            expect $
              QReport_
                anything
                (hasSubstr "Expected GHC.Types.Int to be a class")
                |-> ()

            _ <- runQ (makeMockable ''Int)
            return ()

      wrongKind `shouldThrow` anyIOException

  it "fails when given an unexpected type construct" $
    example $ do
      let notClass = runMockT $ do
            expect $ QReport_ anything (hasSubstr "Expected a class") |-> ()

            _ <- runQ (makeMockableType [t|(Int, String)|])
            return ()

      notClass `shouldThrow` anyIOException

  it "fails when class has no params" $
    example $ do
      let tooManyParams = runMockT $ do
            expectAny $
              QReify ''ClassWithNoParams |-> $(reifyStatic ''ClassWithNoParams)
            expect $
              QReport_
                anything
                (hasSubstr "ClassWithNoParams has no type parameters")
                |-> ()

            _ <- runQ (makeMockable ''ClassWithNoParams)
            return ()

      tooManyParams `shouldThrow` anyIOException

  it "fails when class has no mockable methods" $
    example $ do
      let noMockableMethods = runMockT $ do
            expectAny $ QReify ''Show |-> $(reifyStatic ''Show)
            expect $
              QReport_ anything (hasSubstr "has no mockable methods") |-> ()

            _ <- runQ (deriveMockable ''Show)
            return ()

      noMockableMethods `shouldThrow` anyIOException

classTests :: SpecWith ()
classTests = describe "makeMockable" $ do
  simpleTests
  suffixTests
  setupTests
  superTests
  mptcTests
  fdSpecializedTests
  fdGeneralTests
  fdMixedTests
  polyArgTests
  unshowableArgTests
  monadInArgTests
  extraneousMembersTests
  rankNTests
  laxityTests
  nestedNoDefTests
  errorTests
