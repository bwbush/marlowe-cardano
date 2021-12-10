module Component.MetadataTab.View (metadataView) where

import Prologue hiding (div, min)

import Component.MetadataTab.Types (MetadataAction(..))
import Data.Array (concat, concatMap)
import Data.Foldable (foldMap)
import Data.Int as Int
import Data.Lens (Lens', (^.))
import Data.List (List)
import Data.Map (Map)
import Data.Map as Map
import Data.Map.Ordered.OMap (OMap)
import Data.Map.Ordered.OMap as OMap
import Data.Set (Set, toUnfoldable)
import Data.Set.Ordered.OSet (OSet)
import Data.Tuple.Nested (type (/\), (/\))
import Halogen.Classes (btn, minusBtn, plusBtn)
import Halogen.HTML
  ( ClassName(..)
  , HTML
  , button
  , div
  , em_
  , h6_
  , input
  , option
  , select
  , text
  )
import Halogen.HTML.Events (onClick, onValueChange)
import Halogen.HTML.Properties
  ( InputType(..)
  , class_
  , classes
  , min
  , placeholder
  , required
  , selected
  , type_
  , value
  )
import Marlowe.Extended
  ( contractTypeArray
  , contractTypeInitials
  , contractTypeName
  , initialsToContractType
  )
import Marlowe.Extended.Metadata
  ( ChoiceInfo
  , MetaData
  , MetadataHintInfo
  , NumberFormat(..)
  , NumberFormatType(..)
  , ValueParameterInfo
  , _choiceInfo
  , _choiceNames
  , _roleDescriptions
  , _roles
  , _slotParameterDescriptions
  , _slotParameters
  , _valueParameterInfo
  , _valueParameters
  , defaultForFormatType
  , fromString
  , getFormatType
  , isDecimalFormat
  , isDefaultFormat
  , toString
  )

onlyDescriptionRenderer
  :: forall a p
   . (String -> String -> a)
  -> (String -> a)
  -> String
  -> String
  -> Boolean
  -> String
  -> String
  -> Array (HTML p a)
onlyDescriptionRenderer
  setAction
  deleteAction
  key
  info
  needed
  typeNameTitle
  typeNameSmall =
  [ div [ class_ $ ClassName "metadata-prop-label" ]
      [ text $ typeNameTitle <> " " <> show key <> ": " ]
  , div [ class_ $ ClassName "metadata-prop-edit" ]
      [ input
          [ type_ InputText
          , placeholder $ "Description for " <> typeNameSmall <> " " <> show key
          , class_ $ ClassName "metadata-input"
          , value info
          , onValueChange $ setAction key
          ]
      ]
  , div [ class_ $ ClassName "metadata-prop-delete" ]
      [ button
          [ classes
              [ if needed then plusBtn else minusBtn
              , ClassName "align-top"
              , btn
              ]
          , onClick $ const $ deleteAction key
          ]
          [ text "-" ]
      ]
  ]
    <>
      if needed then []
      else
        [ div
            [ classes
                [ ClassName "metadata-error"
                , ClassName "metadata-prop-not-used"
                ]
            ]
            [ text "Not used" ]
        ]

type FormattedNumberInfo
  =
  { key :: String
  , description :: String
  , format :: NumberFormat
  , setFormat :: String -> NumberFormat -> MetadataAction
  , setDescription :: String -> String -> MetadataAction
  , deleteInfo :: String -> MetadataAction
  }

formattedNumberMetadataRenderer
  :: forall p
   . FormattedNumberInfo
  -> Boolean
  -> String
  -> String
  -> Array (HTML p MetadataAction)
formattedNumberMetadataRenderer
  { key, description, format, setFormat, setDescription, deleteInfo }
  needed
  typeNameTitle
  typeNameSmall =
  [ div [ class_ $ ClassName "metadata-prop-label" ]
      [ text $ typeNameTitle <> " " <> show key <> ": " ]
  , div [ class_ $ ClassName "metadata-prop-formattednum-col1" ]
      [ select
          [ class_ $ ClassName "metadata-input"
          , onValueChange $ setFormat key <<< setNumberFormatType
          ]
          [ option
              [ value $ toString DefaultFormatType
              , selected $ isDefaultFormat format
              ]
              [ text $ "Default format"
              ]
          , option
              [ value $ toString DecimalFormatType
              , selected $ isDecimalFormat format
              ]
              [ text $ "Fixed point amount"
              ]
          ]
      ]
  , div [ class_ $ ClassName "metadata-prop-formattednum-col2" ]
      [ input
          [ type_ InputText
          , placeholder $ "Description for " <> typeNameSmall <> " " <> show key
          , class_ $ ClassName "metadata-input"
          , value description
          , onValueChange $ setDescription key
          ]
      ]
  , div [ class_ $ ClassName "metadata-prop-delete" ]
      [ button
          [ classes
              [ if needed then plusBtn else minusBtn
              , ClassName "align-top"
              , btn
              ]
          , onClick $ const $ deleteInfo key
          ]
          [ text "-" ]
      ]
  ]
    <>
      ( if needed then []
        else
          [ div
              [ classes
                  [ ClassName "metadata-error"
                  , ClassName "metadata-prop-not-used"
                  ]
              ]
              [ text "Not used" ]
          ]
      )
    <> case format of
      DefaultFormat -> []
      DecimalFormat numDecimals labelStr ->
        [ div [ class_ $ ClassName "metadata-prop-formattednum-col1" ]
            [ input
                [ type_ InputNumber
                , placeholder $ "Number of decimal digits for " <> typeNameSmall
                    <> " "
                    <> show key
                , class_ $ ClassName "metadata-input"
                , value $ if numDecimals == 0 then "" else show numDecimals
                , required true
                , min zero
                , onValueChange $ setFormat key <<< setDecimals labelStr
                ]
            ]
        , div [ class_ $ ClassName "metadata-prop-formattednum-col2" ]
            [ input
                [ type_ InputText
                , placeholder $ "Currency label for " <> typeNameSmall <> " " <>
                    show key
                , class_ $ ClassName "metadata-input"
                , value labelStr
                , onValueChange $ setFormat key <<< DecimalFormat numDecimals
                ]
            ]
        ]
      TimeFormat -> []
  where
  setNumberFormatType :: String -> NumberFormat
  setNumberFormatType str = case fromString str of
    Just formatType
      | formatType == getFormatType format -> format
      | otherwise -> defaultForFormatType formatType
    Nothing -> defaultForFormatType DefaultFormatType

  setDecimals :: String -> String -> NumberFormat
  setDecimals labelStr x =
    DecimalFormat
      ( case Int.fromString x of
          Just y
            | y >= 0 -> y
          _ -> 0
      )
      labelStr

choiceMetadataRenderer
  :: forall p
   . String
  -> ChoiceInfo
  -> Boolean
  -> String
  -> String
  -> Array (HTML p MetadataAction)
choiceMetadataRenderer key { choiceDescription, choiceFormat } =
  formattedNumberMetadataRenderer
    { key: key
    , description: choiceDescription
    , format: choiceFormat
    , setFormat: SetChoiceFormat
    , setDescription: SetChoiceDescription
    , deleteInfo: DeleteChoiceInfo
    }

valueParameterMetadataRenderer
  :: forall p
   . String
  -> ValueParameterInfo
  -> Boolean
  -> String
  -> String
  -> Array (HTML p MetadataAction)
valueParameterMetadataRenderer
  key
  { valueParameterDescription, valueParameterFormat } =
  formattedNumberMetadataRenderer
    { key: key
    , description: valueParameterDescription
    , format: valueParameterFormat
    , setFormat: SetValueParameterFormat
    , setDescription: SetValueParameterDescription
    , deleteInfo: DeleteValueParameterInfo
    }

metadataList
  :: forall b c p
   . Map String c
  -> Set String
  -> (String -> c -> Boolean -> String -> String -> Array (HTML p b))
  -> String
  -> String
  -> (String -> b)
  -> Array (HTML p b)
metadataList
  metadataMap
  hintSet
  metadataRenderer
  typeNameTitle
  typeNameSmall
  setEmptyMetadata =
  if Map.isEmpty combinedMap then
    []
  else
    [ div [ class_ $ ClassName "metadata-group-title" ]
        [ h6_ [ em_ [ text $ typeNameTitle <> " descriptions" ] ] ]
    ]
      <>
        ( concatMap
            ( \(key /\ val) ->
                ( case val of
                    Just (info /\ needed) -> metadataRenderer key info needed
                      typeNameTitle
                      typeNameSmall
                    Nothing ->
                      [ div
                          [ classes
                              [ ClassName "metadata-error"
                              , ClassName "metadata-prop-not-defined"
                              ]
                          ]
                          [ text $ typeNameTitle <> " " <> show key <>
                              " meta-data not defined"
                          ]
                      , div [ class_ $ ClassName "metadata-prop-create" ]
                          [ button
                              [ classes [ minusBtn, ClassName "align-top", btn ]
                              , onClick $ const $ (setEmptyMetadata key)
                              ]
                              [ text "+" ]
                          ]
                      ]
                )
            )
            $ Map.toUnfoldable combinedMap
        )
  where
  mergeMaps
    :: forall c2
     . (Maybe (c2 /\ Boolean))
    -> (Maybe (c2 /\ Boolean))
    -> (Maybe (c2 /\ Boolean))
  mergeMaps (Just (x /\ _)) _ = Just (x /\ true)

  mergeMaps _ _ = Nothing

  -- The value of the Map has the following meaning:
  -- * Nothing means the entry is in the contract but not in the metadata
  -- * Just (_ /\ false) means the entry is in the metadata but not in the contract
  -- * Just (_ /\ true) means the entry is both in the contract and in the metadata
  -- If it is nowhere we just don't store it in the map
  combinedMap =
    Map.unionWith mergeMaps
      (map (\x -> Just (x /\ false)) metadataMap)
      ( Map.fromFoldable
          (map (\x -> x /\ Nothing) ((toUnfoldable hintSet) :: List String))
      )

sortableMetadataList
  :: forall a c p
   . OMap String c
  -> OSet String
  -> (String -> c -> Boolean -> String -> String -> Array (HTML p a))
  -> String
  -> String
  -> (String -> a)
  -> Array (HTML p a)
sortableMetadataList
  metadataMap
  hintSet
  metadataRenderer
  typeNameTitle
  typeNameSmall
  setEmptyMetadata =
  if OMap.isEmpty combinedMap then
    []
  else
    [ div [ class_ $ ClassName "metadata-group-title" ]
        [ h6_ [ em_ [ text $ typeNameTitle <> " descriptions" ] ] ]
    ]
      <>
        ( concatMap
            ( \(key /\ val) ->
                ( case val of
                    Just (info /\ needed) -> metadataRenderer key info needed
                      typeNameTitle
                      typeNameSmall
                    Nothing ->
                      [ div
                          [ classes
                              [ ClassName "metadata-error"
                              , ClassName "metadata-prop-not-defined"
                              ]
                          ]
                          [ text $ typeNameTitle <> " " <> show key <>
                              " meta-data not defined"
                          ]
                      , div [ class_ $ ClassName "metadata-prop-create" ]
                          [ button
                              [ classes [ minusBtn, ClassName "align-top", btn ]
                              , onClick $ const $ setEmptyMetadata key
                              ]
                              [ text "+" ]
                          ]
                      ]
                )
            )
            $ OMap.toUnfoldable combinedMap
        )
  where
  mergeMaps
    :: forall c2
     . (Maybe (c2 /\ Boolean))
    -> (Maybe (c2 /\ Boolean))
    -> (Maybe (c2 /\ Boolean))
  mergeMaps (Just (x /\ _)) _ = Just (x /\ true)

  mergeMaps _ _ = Nothing

  -- The value of the Map has the following meaning:
  -- * Nothing means the entry is in the contract but not in the metadata
  -- * Just (_ /\ false) means the entry is in the metadata but not in the contract
  -- * Just (_ /\ true) means the entry is both in the contract and in the metadata
  -- If it is nowhere we just don't store it in the map
  combinedMap =
    OMap.unionWith mergeMaps
      (map (\x -> Just (x /\ false)) metadataMap)
      (foldMap (\x -> OMap.singleton x Nothing) hintSet)

metadataView :: forall p. MetadataHintInfo -> MetaData -> HTML p MetadataAction
metadataView metadataHints metadata =
  div [ classes [ ClassName "metadata-form" ] ]
    ( concat
        [ [ div [ class_ $ ClassName "metadata-mainprop-label" ]
              [ text "Contract type: " ]
          , div [ class_ $ ClassName "metadata-mainprop-edit" ]
              [ select
                  [ class_ $ ClassName "metadata-input"
                  , onValueChange $ SetContractType <<< initialsToContractType
                  ]
                  do
                    ct <- contractTypeArray
                    pure
                      $ option
                          [ value $ contractTypeInitials ct
                          , selected (ct == metadata.contractType)
                          ]
                          [ text $ contractTypeName ct
                          ]
              ]
          ]
        , [ div [ class_ $ ClassName "metadata-mainprop-label" ]
              [ text "Contract name: " ]
          , div [ class_ $ ClassName "metadata-mainprop-edit" ]
              [ input
                  [ type_ InputText
                  , placeholder "Contract name"
                  , class_ $ ClassName "metadata-input"
                  , value metadata.contractName
                  , onValueChange $ SetContractName
                  ]
              ]
          ]
        , [ div [ class_ $ ClassName "metadata-mainprop-label" ]
              [ text "Contract short description: " ]
          , div [ class_ $ ClassName "metadata-mainprop-edit" ]
              [ input
                  [ type_ InputText
                  , placeholder "Contract description"
                  , class_ $ ClassName "metadata-input"
                  , value metadata.contractShortDescription
                  , onValueChange $ SetContractShortDescription
                  ]
              ]
          ]
        , [ div [ class_ $ ClassName "metadata-mainprop-label" ]
              [ text "Contract long description: " ]
          , div [ class_ $ ClassName "metadata-mainprop-edit" ]
              [ input
                  [ type_ InputText
                  , placeholder "Contract description"
                  , class_ $ ClassName "metadata-input"
                  , value metadata.contractLongDescription
                  , onValueChange $ SetContractLongDescription
                  ]
              ]
          ]
        , generateMetadataList _roleDescriptions _roles
            (onlyDescriptionRenderer SetRoleDescription DeleteRoleDescription)
            "Role"
            "role"
            (\x -> SetRoleDescription x mempty)
        , generateMetadataList _choiceInfo _choiceNames choiceMetadataRenderer
            "Choice"
            "choice"
            (\x -> SetChoiceDescription x mempty)
        , generateSortableMetadataList _slotParameterDescriptions
            _slotParameters
            ( onlyDescriptionRenderer SetSlotParameterDescription
                DeleteSlotParameterDescription
            )
            "Slot parameter"
            "slot parameter"
            (\x -> SetSlotParameterDescription x mempty)
        , generateSortableMetadataList _valueParameterInfo _valueParameters
            valueParameterMetadataRenderer
            "Value parameter"
            "value parameter"
            (\x -> SetValueParameterDescription x mempty)
        ]
    )
  where
  generateMetadataList
    :: forall c
     . Lens' MetaData (Map String c)
    -> Lens' MetadataHintInfo (Set String)
    -> ( String
         -> c
         -> Boolean
         -> String
         -> String
         -> Array (HTML p MetadataAction)
       )
    -> String
    -> String
    -> (String -> MetadataAction)
    -> Array (HTML p MetadataAction)
  generateMetadataList mapLens setLens = metadataList (metadata ^. mapLens)
    (metadataHints ^. setLens)

  generateSortableMetadataList
    :: forall c
     . Lens' MetaData (OMap String c)
    -> Lens' MetadataHintInfo (OSet String)
    -> ( String
         -> c
         -> Boolean
         -> String
         -> String
         -> Array (HTML p MetadataAction)
       )
    -> String
    -> String
    -> (String -> MetadataAction)
    -> Array (HTML p MetadataAction)
  generateSortableMetadataList mapLens setLens = sortableMetadataList
    (metadata ^. mapLens)
    (metadataHints ^. setLens)

