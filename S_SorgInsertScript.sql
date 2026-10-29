do $$ begin if( not exists( select * from public.s_sorg where kor = 270584)) then 
INSERT INTO public.s_sorg (kor, c_obl, snam, name, inn, ogrn, address, okpo, archive) VALUES (270584, 27, 'ООО "ПМК-83"', 'ООО "Передвижная механизированная колонна № 83"', 2712000131, 1022700758486, '681060, Хабаровский край, Комсомольский р-н, село Хурба, ул Гайдара, д 17', 1007381, false);  
ELSE 
UPDATE  public.s_sorg set okpo = 1007381 
where kor = 270584; 
end if; end $$; 