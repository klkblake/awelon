Still thinking about this (additive conjunction). I need a really good use-case for them that wouldn't be better handled by sending some typereps backwards. Also, it seems feasible to model these using fractional types, as far as the compiler is concerned.

I'd like to model it within the language, not as a primitive, perhaps using fractional types. Until I have a good approach for it, I'll table the idea; there are more important features, such as collections processing...

#### Static Latent Choice

Awelon also supports a concept of latent choice `(x & y)`. This is called additive conjunction in linear logic, and called an 'offer' in Awelon. The intuition is that we are offering x or y, but the choice hasn't been made yet. The utility of latent choice comes from a programmer's ability to continue extrapolating on the different paths before making a choice. 

Latent choice is useful for modeling lookahead searches, or for adaptive software where we want to examine multiple valid static outcomes and pick a 'best' one according to some static heuristic. Simpler searches, e.g. scanning an association list of `(Static Text * value)` pairs, don't require latent choice. Since latent choice can be a relatively expensive compile-time feature, it should be avoided if unnecessary. 

        offerFork   :: x ~> (x & x)
        offerAccept :: (x & y) ~> x
        offerDist   :: (x * (y & z)) ~> ((x * y) & (x * z))
        offerFirst  :: Static (x ~> x') * (x & y) ~> (x' & y)
        offerAssocl :: (x & (y & z)) ~> ((x & y) & z)
        offerSwap   :: (x & y) ~> (y & x)
        %  no unit type, but fork/accept can do the same work

Of course, to actually make choices we need some way to compare them. Developers are able to extract primtive static values from a subprogram to help make a choice or to use in other ways (it might be useful to exchange values between paths).

        offerExtractText :: ((Static Text * x) & y) ~> Static Text * (x & y)
        offerExtractNumber :: ((Static Number * x) & y) ~> Static Number * (x & y)
        offerExtractBlock :: ((Static Block * x) & y) ~> Static Block * (x & y)

Offers are linear; an offer *must* be accepted before the application will compile. 
