<?php

namespace App\Providers;

use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Date;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\URL;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        //
    }

    public function boot(): void
    {
        $this->configureDefaults();
    }

    /**
     * Padrões recomendados para produção.
     */
    protected function configureDefaults(): void
    {
        Date::use(CarbonImmutable::class);

        DB::prohibitDestructiveCommands(app()->isProduction());

        // Em desenvolvimento: acusa N+1, atributos inexistentes e mass assignment silencioso.
        Model::shouldBeStrict(! app()->isProduction());

        // Em produção o app fica atrás do Cloudflare Tunnel (HTTPS lá fora, HTTP aqui dentro):
        // garante que URLs e redirects (inclusive o callback do Google) saiam em https.
        if (app()->isProduction()) {
            URL::forceScheme('https');
        }
    }
}
