module SiteConfig exposing (SiteConfig)

import DataSource exposing (DataSource)
import Head


type alias SiteConfig =
    { canonicalUrl : String
    , head : DataSource Never (List Head.Tag)
    }
